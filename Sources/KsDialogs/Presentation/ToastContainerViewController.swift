#if canImport(UIKit)
import UIKit
import os

/// 1枚の Toast が所有する器 (core/ADR-0030)。
///
/// Loading の器の非モーダル派生である。提示スタックには載せず取り付け先の View (既定では
/// key window) へ直接重ねるところ、レイアウトと演出を Dialog と同じ共有部品
/// (`DialogLayoutApplier` / `DialogTransitionRunner`) に通すところは Loading と同じで、
/// 違うのは次の2点になる。
///
/// - 覆いを持たない。背後は一切暗くならない
/// - 入力を一切受け取らない。ルート View がすべてのタッチを素通しする (core/ADR-0031)
///
/// 配置の実効値は「show 引数 > 中身への添付 > `ToastStyle` のアプリ既定配置 > Toast の契約既定値」の
/// 優先順で決まる。器はそのうち後ろ2段をまとめた `fallbackPlacement` を受け取り、
/// 前2段を Dialog / Loading と同じ規則で読む (core/ADR-0015)。
@MainActor
final class ToastContainerViewController: UIViewController {
    /// 初回レイアウトパスの中で添付を読み直す回数の上限。
    private static let maxSnapshotConvergencePasses = 4

    /// 添付値の到達を待つために追加で走らせるレイアウトパスの上限。
    private static let maxAttributeSupplyWaitPasses = 1

    /// 供給元の不具合を知らせるための記録口。
    private static let logger = Logger(subsystem: "jp.kamusoft.ksdialogs", category: "toast")

    let contentView: UIView

    /// 中身を所有するホスト。宣言的 UI の中身のときだけ存在し、撤去時に外して解放する。
    private(set) var contentHost: UIViewController?

    private let showPlacement: DialogPlacement?

    /// show 引数も添付も無いときに採用する配置。
    private let fallbackPlacement: DialogPlacement

    /// 実効値のレイアウトを中身へ反映する部品。
    private let layoutApplier: DialogLayoutApplier

    /// 出入りのフックを走らせる部品。Toast は覆いを持たないため、覆いは器へ敷かない。
    private let transitionRunner: DialogTransitionRunner

    /// 現時点の実効値。初回レイアウトパスの完了時点で固定される。
    private var layout: DialogLayout

    /// 実効値を固定したか。true 以降は添付を読み直さない。
    private(set) var isLayoutSnapshotFrozen = false

    /// 添付値の到達待ちを走らせたか。上限は1回なので二重には走らせない。
    private var didScheduleAttributeSupplyWait = false

    /// 進行中の入りの演出。撤去に移るときに取り消す。
    private var presentationTask: Task<Void, Never>?

    /// 撤去まで進んだか。撤去の要求が重なっても1回しか進まないための印。
    private var isRemoved = false

    /// 中身が元々持っていた透明度。演出を始めるときにこの値へ戻す。
    private var contentInitialAlpha: CGFloat = 1

    /// 実効値と同じ時点で固定された出入りの演出。固定前は nil。
    var resolvedTransition: DialogTransition? {
        transitionRunner.resolvedTransition
    }

    /// - Parameters:
    ///   - content: Toast の中身の内部表現。添付された `ksDialogOptions` / `ksDialogPlacement` /
    ///     `ksDialogTransition` が実効値の供給元になる
    ///   - placement: 表示 API の引数で渡された配置。nil でなければ添付された placement を
    ///     まるごと置換する (core/ADR-0015)
    ///   - fallbackPlacement: show 引数も添付も無いときに採る配置
    init(content: DialogContent, placement: DialogPlacement?, fallbackPlacement: DialogPlacement) {
        self.contentView = content.view
        self.contentHost = content.host
        self.showPlacement = placement
        self.fallbackPlacement = fallbackPlacement
        self.layoutApplier = DialogLayoutApplier(contentView: content.view)
        self.transitionRunner = DialogTransitionRunner(contentView: content.view)
        self.layout = DialogLayout(
            options: DialogOptions(),
            placement: placement ?? fallbackPlacement
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("This ViewController does not support instantiation from a storyboard.")
    }

    override func loadView() {
        let rootView = ToastContainerRootView()
        rootView.onAttachedToWindow = { [weak self] in
            self?.settleLayoutSnapshotOnScreen()
        }
        rootView.onWillLayoutSubviews = { [weak self] in
            self?.updateLayoutForCurrentBounds()
        }
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // 覆いを敷かないので、器の面は見えも当たり判定も持たない。
        view.isUserInteractionEnabled = false

        if let contentHost {
            addChild(contentHost)
        }
        contentInitialAlpha = contentView.alpha
        // 演出を始めるまで中身は見せない。最終位置が演出より先に見えるのを防ぐ。
        contentView.alpha = 0
        layoutApplier.install(in: view)
        contentHost?.didMove(toParent: self)
        layoutApplier.rebuildConstraints(for: layout)
    }

    /// 器を取り付け先へ重ねる。
    ///
    /// 取り付け先の寸法に追随させるので、回転・リサイズでは器の矩形が自動で更新され、
    /// そのレイアウトパスの中で固定済みの実効値から位置とサイズが導き直される。
    /// - Parameters:
    ///   - hostView: 器を重ねる先
    ///   - siblingBelow: この View より下に入れる。Loading が表示中ならその器の View を渡すことで
    ///     Loading が常に Toast より前面になる (core/ADR-0030)。nil なら最前面へ重ねる
    func attach(to hostView: UIView, below siblingBelow: UIView? = nil) {
        loadViewIfNeeded()
        // ウィンドウに載る前に矩形を確定させる。載った瞬間に走る初回パスの入力になるため、
        // 順序を逆にすると実効値が寸法ゼロの状態で固定される。
        view.frame = hostView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let siblingBelow, siblingBelow.superview === hostView {
            hostView.insertSubview(view, belowSubview: siblingBelow)
        } else {
            hostView.addSubview(view)
        }
        hostView.layoutIfNeeded()
    }

    /// 出の演出を走らせてから器を取り付け先から外す。撤去が完了してから戻る。
    func dismiss() async {
        guard !isRemoved else { return }
        isRemoved = true
        presentationTask?.cancel()
        presentationTask = nil
        // 実効値が固まる前に閉じる経路では演出そのものが成立しないため、撤去だけを行う。
        if isLayoutSnapshotFrozen {
            await transitionRunner.runDismissalPhase()
        }
        releaseContentHost()
        view.removeFromSuperview()
    }

    // MARK: - 実効値の固定

    /// 器が画面に載った直後に、その状態での初回レイアウトパスを走らせて実効値を固定する
    /// (core/ADR-0015 の境界を Dialog の器と揃える)。
    private func settleLayoutSnapshotOnScreen() {
        guard !isLayoutSnapshotFrozen else { return }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        guard !isAttributeSupplyPending else {
            scheduleAttributeSupplyWait()
            return
        }
        settleLayoutSnapshot()
    }

    /// 添付値の供給がまだ届いていない中身か。到達状態を知らせない中身では常に false。
    private var isAttributeSupplyPending: Bool {
        guard let probe = contentView as? any DialogAttributeSupplyProbe else { return false }
        return !probe.hasResolvedAttributeSupply
    }

    /// 次の main runloop サイクルで追加のレイアウトパスを1回だけ走らせ、そのあと実効値を固定する。
    /// 上限に達しても添付が届かなければ添付なしとして既定値を採用する (core/ADR-0015)。
    private func scheduleAttributeSupplyWait() {
        guard !didScheduleAttributeSupplyWait else { return }
        didScheduleAttributeSupplyWait = true
        Task { @MainActor [weak self] in
            guard let self, !self.isLayoutSnapshotFrozen, !self.isRemoved else { return }
            for _ in 0..<Self.maxAttributeSupplyWaitPasses {
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                if !self.isAttributeSupplyPending { break }
            }
            if self.isAttributeSupplyPending {
                Self.logger.warning(
                    "No attachment values were received from the Toast content; presenting with the default placement."
                )
            }
            self.settleLayoutSnapshot()
        }
    }

    /// 走り終えたレイアウトパスの時点の添付値で実効値を固定し、入りの演出へ進む。
    private func settleLayoutSnapshot() {
        guard !isLayoutSnapshotFrozen, !isRemoved else { return }
        var remainingPasses = Self.maxSnapshotConvergencePasses
        while remainingPasses > 0, refreshLayoutSnapshotIfChanged() {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            remainingPasses -= 1
        }
        if remainingPasses == 0, hasPendingSupplyChange {
            Self.logger.warning(
                "The Toast attachments did not converge; using the values from layout pass \(Self.maxSnapshotConvergencePasses)."
            )
        }
        isLayoutSnapshotFrozen = true
        transitionRunner.settleSnapshot(attached: contentView.ksDialogTransition)
        beginPresentation()
    }

    /// 添付を読み直し、実効値が変わっていれば実効値と制約を組み直す。
    /// - Returns: 組み直したら true。固定済みか変化がなければ false。
    @discardableResult
    private func refreshLayoutSnapshotIfChanged() -> Bool {
        guard !isLayoutSnapshotFrozen else { return false }
        let composed = composedLayout()
        guard composed != layout else { return false }
        layout = composed
        guard isViewLoaded else { return true }
        layoutApplier.rebuildConstraints(for: layout)
        return true
    }

    /// 「show 引数 > 中身への添付 > style のアプリ既定配置 > 契約既定値」の優先順で読んだ実効値。
    /// 後ろ2段は `fallbackPlacement` に畳み込まれている。
    private func composedLayout() -> DialogLayout {
        DialogLayout(
            options: contentView.ksDialogOptions ?? DialogOptions(),
            placement: showPlacement ?? contentView.ksDialogPlacement ?? fallbackPlacement
        )
    }

    /// 添付の書き換えで実効値が変わっているか。読むだけで実効値は変えない。
    private var hasPendingSupplyChange: Bool {
        !isLayoutSnapshotFrozen && composedLayout() != layout
    }

    /// このレイアウトパスの寸法・可視領域で位置とサイズを導き直す。
    private func updateLayoutForCurrentBounds() {
        _ = refreshLayoutSnapshotIfChanged()
        layoutApplier.updateForCurrentBounds(layout: layout)
    }

    // MARK: - 出入りの演出

    /// 出現の演出を始める (core/ADR-0017)。表示の呼び出し元はこの完了を待たない。
    private func beginPresentation() {
        presentationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, !self.isRemoved else { return }
            await self.transitionRunner.runPresentationPhase {
                self.contentView.alpha = self.contentInitialAlpha
            }
        }
    }

    /// 中身のホストを child containment から外して解放する。
    private func releaseContentHost() {
        guard let contentHost else { return }
        self.contentHost = nil
        contentHost.willMove(toParent: nil)
        contentHost.view.removeFromSuperview()
        contentHost.removeFromParent()
    }
}
#endif
