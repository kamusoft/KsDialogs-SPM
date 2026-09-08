#if canImport(UIKit)
import UIKit
import os

/// Loading の器の覆いになる面。
/// ウィンドウに載った瞬間とレイアウトパスの開始を器へ知らせる。
///
/// Dialog の器と違い提示機構を通らないため、`UIViewController` の出現通知に頼らず
/// この View の生の通知でレイアウトの節目を捉える。
final class LoadingContainerRootView: UIView {
    /// ウィンドウに載ったときに呼ばれる。
    var onAttachedToWindow: (() -> Void)?

    /// レイアウトパスに入るときに呼ばれる。
    var onWillLayoutSubviews: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        onAttachedToWindow?()
    }

    override func layoutSubviews() {
        onWillLayoutSubviews?()
        super.layoutSubviews()
    }
}

/// 1回の表示が所有する Loading の器 (core/ADR-0022・core/ADR-0026)。
///
/// Dialog 機構の提示スタックには載せず、取り付け先の View (既定では key window) へ直接重ねる。
/// 背景の覆いと中身の配置・出入りの演出は Dialog の器と同じ共有部品
/// (`DialogLayoutApplier` / `DialogTransitionRunner`) を通すため、
/// レイアウト規則と演出の意味は Dialog と同一になる。
///
/// Loading はユーザー操作では閉じないため、外側タップの扱いは持たない。
/// 覆いは入力を受け取り背後へ透過させないので、`isCanceledOnTouchOutside` は常に無効である。
@MainActor
final class LoadingContainerViewController: UIViewController {
    /// 初回レイアウトパスの中で添付を読み直す回数の上限。
    private static let maxSnapshotConvergencePasses = 4

    /// 添付値の到達を待つために追加で走らせるレイアウトパスの上限。
    private static let maxAttributeSupplyWaitPasses = 1

    /// 供給元の不具合を知らせるための記録口。
    private static let logger = Logger(subsystem: "jp.kamusoft.ksdialogs", category: "loading")

    let contentView: UIView

    /// 中身を所有するホスト。宣言的 UI の中身のときだけ存在し、撤去時に外して解放する。
    private(set) var contentHost: UIViewController?

    private let showPlacement: DialogPlacement?

    /// 実効値のレイアウトを中身へ反映する部品。
    private let layoutApplier: DialogLayoutApplier

    /// 覆いのフェードと出入りのフックを走らせる部品。
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

    /// 背景の覆い。
    var overlayView: UIView {
        transitionRunner.overlayView
    }

    /// 実効値と同じ時点で固定された出入りの演出。固定前は nil。
    var resolvedTransition: DialogTransition? {
        transitionRunner.resolvedTransition
    }

    /// - Parameters:
    ///   - content: Loading の中身の内部表現。添付された `ksDialogOptions` / `ksDialogPlacement` /
    ///     `ksDialogTransition` が実効値の供給元になる (既定ローディングでは設定プロパティの値が
    ///     添付として載っている)
    ///   - placement: 表示 API の引数で渡された配置。nil でなければ添付された placement を
    ///     まるごと置換する (core/ADR-0015)
    init(content: DialogContent, placement: DialogPlacement?) {
        self.contentView = content.view
        self.contentHost = content.host
        self.showPlacement = placement
        self.layout = DialogLayout.composed(showPlacement: placement, attachedOn: content.view)
        self.layoutApplier = DialogLayoutApplier(contentView: content.view)
        self.transitionRunner = DialogTransitionRunner(contentView: content.view)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("This ViewController does not support instantiation from a storyboard.")
    }

    override func loadView() {
        let rootView = LoadingContainerRootView()
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
        // 覆いと中身を兄弟のレイヤに分け、覆いのフェードが中身を巻き込まないようにする (core/ADR-0017)。
        view.backgroundColor = .clear
        // 覆いが入力を吸収し、背後の画面・ダイアログへ届かせない。
        view.isUserInteractionEnabled = true
        transitionRunner.installOverlay(in: view, color: layout.overlayColor)

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
    /// この呼び出しが戻った時点で覆いは入力を吸収しており、操作ブロックが有効になっている。
    func attach(to hostView: UIView) {
        loadViewIfNeeded()
        // ウィンドウに載る前に矩形を確定させる。載った瞬間に走る初回パスの入力になるため、
        // 順序を逆にすると実効値が寸法ゼロの状態で固定される。
        view.frame = hostView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostView.addSubview(view)
        hostView.layoutIfNeeded()
    }

    /// 出の演出を走らせてから器を取り付け先から外す。
    /// 撤去が完了してから戻るので、戻った時点で操作ブロックは解除されている。
    func dismiss() async {
        guard !isRemoved else { return }
        isRemoved = true
        view.isUserInteractionEnabled = false
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
    /// 上限に達しても添付が届かなければ添付なしとして契約既定値を採用する (core/ADR-0015)。
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
                    "No attachment values were received from the Loading content; presenting with the contract defaults."
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
                "The Loading attachments did not converge; using the values from layout pass \(Self.maxSnapshotConvergencePasses)."
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
        transitionRunner.applyOverlayColor(layout.overlayColor)
        layoutApplier.rebuildConstraints(for: layout)
        return true
    }

    /// 「表示 API 引数 > コンテンツ添付 > 契約既定値」の優先順で読んだ、その時点の実効値。
    private func composedLayout() -> DialogLayout {
        DialogLayout.composed(showPlacement: showPlacement, attachedOn: contentView)
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

    /// 覆いのフェードと出現の演出を始める (core/ADR-0017)。
    /// 表示の呼び出し元はこの完了を待たない — 操作ブロックは器を重ねた時点で有効になっている。
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
