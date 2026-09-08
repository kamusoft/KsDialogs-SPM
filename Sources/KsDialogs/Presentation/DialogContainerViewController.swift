#if canImport(UIKit)
import UIKit
import os

/// 器の覆いになる面。ウィンドウに載った瞬間を器へ知らせる。
///
/// 契約が定める実効値のスナップショット時点は「器を画面に載せたあと、最初のレイアウトが終わった時点」
/// なので、その最初のレイアウトが必ず1回走るようにするための足がかりとして使う。
private final class DialogContainerRootView: UIView {
    /// ウィンドウに載ったときに呼ばれる。
    var onAttachedToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        onAttachedToWindow?()
    }
}

/// 1回の show が所有するダイアログの器。
/// 背景の覆い (scrim) と中身の View の配置、外側タップのキャンセル、出入りの演出、自分自身の閉鎖を受け持つ。
@MainActor
final class DialogContainerViewController: UIViewController {
    /// 初回レイアウトパスの中で添付を読み直す回数の上限。
    /// 添付が読むたびに変わり続ける供給元でもレイアウトが止まらなくなることを防ぐ。
    private static let maxSnapshotConvergencePasses = 4

    /// 添付値の到達を待つために追加で走らせるレイアウトパスの上限。
    /// 上限に達しても届かなければ添付なしとして扱い、提示を止めない (core/ADR-0015)。
    private static let maxAttributeSupplyWaitPasses = 1

    /// 供給元の不具合を知らせるための記録口。
    private static let logger = Logger(subsystem: "jp.kamusoft.ksdialogs", category: "layout")

    let contentView: UIView

    /// 実効値のレイアウトを中身へ反映する部品。
    private let layoutApplier: DialogLayoutApplier

    /// 覆いのフェードと出入りのフックを走らせる部品。
    private let transitionRunner: DialogTransitionRunner

    /// 背景の覆い。中身の兄弟として敷き、中身とは独立にフェードする。
    var overlayView: UIView {
        transitionRunner.overlayView
    }

    /// 中身を所有するホスト。SwiftUI の中身のときだけ存在し、閉鎖時に child から外して解放する。
    private(set) var contentHost: UIViewController?

    private let showPlacement: DialogPlacement?
    private let resultChannel: DialogResultChannel

    /// 現時点の実効値。初回レイアウトパスの完了時点で固定される。
    private var layout: DialogLayout
    /// 実効値を固定したか。true 以降は添付を読み直さない。
    private(set) var isLayoutSnapshotFrozen = false

    /// 添付値の到達待ちを走らせたか。上限は1回なので二重には走らせない。
    private var didScheduleAttributeSupplyWait = false
    /// 到達待ちの上限に達しても添付値が届かなかったか。届かなければ契約既定値で提示する。
    private(set) var didExhaustAttributeSupplyWait = false

    /// 実効値と同じ時点で固定された出入りの演出。固定前は nil。
    var resolvedTransition: DialogTransition? {
        transitionRunner.resolvedTransition
    }

    /// 固定された覆いのフェード時間。
    var resolvedOverlayDuration: TimeInterval {
        transitionRunner.resolvedOverlayDuration
    }

    /// 器が今どの段階にいるか。
    private(set) var containerState: DialogContainerState = .created

    /// 進行中の演出を進める仕事。脱出口ではこれを取り消して先へ進む。
    private var lifecycleTask: Task<Void, Never>?

    /// 確定した結果を呼び出し元へ届ける口。撤去のあとに1回だけ配送される。
    ///
    /// 器とは別の寿命を持たせてあるので、撤去の完了を待っている間に器が解放されても配送できる。
    /// 器の解放が配送より先に起きたときは `deinit` がこの口へ引き継ぐ。
    nonisolated let outcomeDelivery: DialogOutcomeDelivery

    /// 器を画面から外す口。提示層が受け持つ。
    /// 渡した口は、器が実際に画面から外れ終わった時点で呼ばれる。
    var onDismissRequest: (@MainActor (@escaping DialogRemovalCompletion) -> Void)?

    /// 撤去を提示層へ要求済みか。要求から完了までの間を見分けるための印。
    /// この間の状態は退出中のままで、`removed` になるのは撤去が完了した時点。
    private var isRemovalRequested = false

    /// 撤去のあとの後始末と配送まで進んだか。撤去の通知が重なっても1回しか進まないための印。
    private var didCompleteRemoval = false

    /// 確定した結果を呼び出し元へ配送したか。撤去が終わるまで true にならない。
    var isOutcomeDelivered: Bool {
        outcomeDelivery.isDelivered
    }

    /// 中身が元々持っていた透明度。演出を始めるときにこの値へ戻す。
    private var contentInitialAlpha: CGFloat = 1

    /// - Parameters:
    ///   - content: ダイアログの中身の内部表現。添付された `ksDialogOptions` / `ksDialogPlacement` /
    ///     `ksDialogTransition` が実効値の供給元になる
    ///   - resultChannel: 結果を確定させる口
    ///   - placement: show の引数で渡された配置。nil でなければ添付された placement をまるごと置換する
    ///
    /// 実効値は「show 引数 > コンテンツ添付 > 契約既定値」の優先順で合成する (core/ADR-0015)。
    /// 合成はレイアウトのたびに読み直され、**器を画面に載せたあとの初回レイアウトパスが
    /// 完了した時点の添付値**で固定される。以降に添付が書き換わっても表示は追随しない。
    /// 出入りの演出も同じ時点で固定される (core/ADR-0017)。
    init(
        content: DialogContent,
        resultChannel: DialogResultChannel,
        placement: DialogPlacement? = nil
    ) {
        self.contentView = content.view
        self.contentHost = content.host
        self.resultChannel = resultChannel
        self.outcomeDelivery = DialogOutcomeDelivery(resultChannel: resultChannel)
        self.showPlacement = placement
        self.layout = DialogLayout.composed(showPlacement: placement, attachedOn: content.view)
        self.layoutApplier = DialogLayoutApplier(contentView: content.view)
        self.transitionRunner = DialogTransitionRunner(contentView: content.view)
        super.init(nibName: nil, bundle: nil)
        // 下のダイアログ・画面を残したまま重ねるため全画面の覆いとして提示する。
        // 出入りの演出は器が自前で駆動するので、OS のトランジションは使わない (core/ADR-0017)。
        modalPresentationStyle = .overFullScreen
    }

    /// 従来 View 系の中身を直接受け取る。
    convenience init(
        contentView: UIView,
        resultChannel: DialogResultChannel,
        placement: DialogPlacement? = nil
    ) {
        self.init(
            content: DialogContent(view: contentView),
            resultChannel: resultChannel,
            placement: placement
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("This ViewController does not support instantiation from a storyboard.")
    }

    deinit {
        // 撤去まで進めないまま器が解放されても、待っている呼び出し元を取り残さない。
        // 配送済みなら何も起こらない。
        let delivery = outcomeDelivery
        Task { @MainActor in
            delivery.submitLatchedOutcome()
        }
    }

    override func loadView() {
        let rootView = DialogContainerRootView()
        rootView.onAttachedToWindow = { [weak self] in
            self?.settleLayoutSnapshotOnScreen()
        }
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 覆いと中身を兄弟のレイヤに分け、覆いのフェードが中身を巻き込まないようにする (core/ADR-0017)。
        view.backgroundColor = .clear
        transitionRunner.installOverlay(in: view, color: layout.overlayColor)

        // 宣言的 UI のホストは child containment に組み込み、出現状態の遷移を通す (core/ADR-0011)。
        if let contentHost {
            addChild(contentHost)
        }
        contentInitialAlpha = contentView.alpha
        // 演出を始めるまで中身は見せない。最終位置が演出より先に見えるのを防ぐ。
        contentView.alpha = 0
        layoutApplier.install(in: view)
        contentHost?.didMove(toParent: self)
        layoutApplier.rebuildConstraints(for: layout)

        let backdropTap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap))
        backdropTap.delegate = self
        view.addGestureRecognizer(backdropTap)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // このパスの計算に入る前に添付を読み直す。パスの途中で書き換わった分は
        // パスが終わったあとの突き合わせ (settleLayoutSnapshot) が拾う。
        _ = refreshLayoutSnapshotIfChanged()
        // ウィンドウの大きさと可視領域はこの時点で確定しているため、
        // 同じレイアウトパスの中で制約の値を更新できる。
        layoutApplier.updateForCurrentBounds(layout: layout)
    }

    /// 提示の前に内容のサイズを確定させる。
    /// ViewModel の初期状態を反映した View に対して1回レイアウトを走らせるので、
    /// 提示された時点のダイアログはすでに内容に見合った大きさになっている (core/ADR-0008)。
    ///
    /// この暫定のパスでは実効値をまだ固定しない。固定は器が画面に載ったあとの
    /// 初回レイアウトパスの完了時点で行われ、そこまでに届いた添付変更は採用される (core/ADR-0015)。
    func prepareForPresentation(inBounds bounds: CGRect) {
        loadViewIfNeeded()
        view.frame = bounds
        view.layoutIfNeeded()
    }

    /// 器が画面に載った直後に、その状態での初回レイアウトパスを走らせて実効値を固定する。
    ///
    /// 契約が定めるスナップショット時点は「器を画面に載せたあと、OS が最初にサイズと位置を
    /// 確定させる処理が終わった瞬間」である (core/ADR-0015)。ウィンドウに載ったことが分かる
    /// この時点でパスを1回走らせ切ってから固定することで、その境界を最初の描画より前に作る。
    private func settleLayoutSnapshotOnScreen() {
        guard !isLayoutSnapshotFrozen else { return }
        view.setNeedsLayout()
        // 中身の View まで含めたパスをここで走らせ切る。
        view.layoutIfNeeded()
        guard !isAttributeSupplyPending else {
            // 宣言的 UI の添付がこのパスでは届かなかった。契約が定めるスナップショット時点を
            // 追加パスの完了まで繰り下げ、そこまでに届いた値を採用する (core/ADR-0015)。
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
    ///
    /// 上限に達しても添付が届かなければ添付なしとして契約既定値を採用し、
    /// 供給元の不具合として知らせる。無限に待って提示が止まることは構造的に起こさない。
    private func scheduleAttributeSupplyWait() {
        guard !didScheduleAttributeSupplyWait else { return }
        didScheduleAttributeSupplyWait = true
        Task { @MainActor [weak self] in
            guard let self, !self.isLayoutSnapshotFrozen else { return }
            for _ in 0..<Self.maxAttributeSupplyWaitPasses {
                self.view.setNeedsLayout()
                self.view.layoutIfNeeded()
                if !self.isAttributeSupplyPending { break }
            }
            if self.isAttributeSupplyPending {
                self.didExhaustAttributeSupplyWait = true
                Self.logger.warning(
                    "No attachment values were received from the Dialog content; presenting with the contract defaults."
                )
            }
            self.settleLayoutSnapshot()
        }
    }

    /// 走り終えたレイアウトパスの時点の添付値で実効値を固定する (core/ADR-0015)。
    ///
    /// パスの最中に添付が書き換わっていたらその値で組み直してもう一度回し、
    /// 読み直しても変わらなくなった (収束した) ところで固定する。
    private func settleLayoutSnapshot() {
        guard !isLayoutSnapshotFrozen else { return }
        var remainingPasses = Self.maxSnapshotConvergencePasses
        while remainingPasses > 0, refreshLayoutSnapshotIfChanged() {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            remainingPasses -= 1
        }
        if remainingPasses == 0, hasPendingSupplyChange {
            // 上限まで回しても添付が変わり続けている。採用されるのは最後のパスの値になり、
            // 契約が定める「初回レイアウトパス完了時点の値」とは限らないため、供給元の不具合として知らせる。
            Self.logger.warning(
                "The Dialog attachments did not converge; using the values from layout pass \(Self.maxSnapshotConvergencePasses)."
            )
        }
        isLayoutSnapshotFrozen = true
        transitionRunner.settleSnapshot(attached: contentView.ksDialogTransition)
        beginLifecycle()
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
        // 張る制約の種類 (サイズを固定するか・どの端を固定するか) が変わり得るため組み直す。
        layoutApplier.rebuildConstraints(for: layout)
        return true
    }

    /// 「show 引数 > コンテンツ添付 > 契約既定値」の優先順で読んだ、その時点の実効値。
    private func composedLayout() -> DialogLayout {
        DialogLayout.composed(showPlacement: showPlacement, attachedOn: contentView)
    }

    /// 添付の書き換えで実効値が変わっているか。読むだけで実効値は変えない。
    private var hasPendingSupplyChange: Bool {
        !isLayoutSnapshotFrozen && composedLayout() != layout
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // ここは「閉じられた」とき以外に「上に別の画面が全画面で重なった」ときも通る。
        // 重なっただけの器はまだ生きており、上の画面が閉じれば再び操作できるので確定させない。
        // 提示関係の解除は画面から外れた直後に済むとは限らないため、判定は次の機会に行う。
        //
        // 器を強く捕まえるのは、この1回分の判定を必ず後始末と配送まで進めるため。
        // 判定の前に提示機構が器を手放すと、撤去まで進めないまま呼び出し元が取り残される。
        Task { @MainActor in
            // 提示関係がまだ解けていなければ、器は画面へ戻り得るか、撤去の完了通知がこれから届く。
            guard self.presentingViewController == nil else { return }
            guard self.isRemovalRequested else {
                // 器は自分から要求していない事情で画面を失っている。
                self.handleHostLost()
                return
            }
            // 自分から要求した撤去が画面上で完了した。提示層からの完了通知と同じ意味を持つので、
            // どちらか先に届いた方で後始末と配送へ進む (提示機構の完了通知が届かない環境でも止まらない)。
            self.completeRemoval()
        }
    }

    // MARK: - 状態機械

    /// 器が画面に載り実効値が固まった時点から、出入りの進行を始める (core/ADR-0017)。
    private func beginLifecycle() {
        guard containerState == .created else { return }
        containerState = .attached
        if resultChannel.isResultSettled {
            // 提示が始まる前に閉鎖信号が来ていた。演出は成立しないので撤去だけを行う。
            scheduleImmediateRemoval()
            return
        }
        beginPresentation()
    }

    /// 提示より前の撤去を、提示処理の外で行う。
    /// 器を画面へ載せている最中に外し返すと提示機構の状態が壊れるため、1度譲ってから撤去する。
    private func scheduleImmediateRemoval() {
        Task { @MainActor [weak self] in
            guard let self, self.containerState == .attached else { return }
            self.finishRemoval()
        }
    }

    /// 覆いのフェードと出現の演出を始める。
    ///
    /// 中身を見せるのも段階を提示中へ進めるのも、進行を始める仕事の中 (`runPresentationPhase` と
    /// その手前) で行い、この呼び出しの中ではしない。ここで見せてしまうと、仕事が動き出すまでの
    /// 間に最終位置のままの中身が描かれ得る。段階だけを先に進めた場合も、まだ何も見えていないのに
    /// 提示中として扱われる隙間ができ、その隙間に届いた閉鎖信号が演出つきで処理されてしまう
    /// (core/ADR-0017)。
    private func beginPresentation() {
        lifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 仕事が動き出すまでの間に閉鎖信号が来ていたときは、提示そのものが成立しない。
            // 見せる相手がいない演出を走らせると、退出しか残っていない器に中身が一瞬映るため、
            // 両フックとも実行せず撤去だけを行う。
            //
            // 確定済みかどうかの判定と提示中への切り替えは同じ同期区間に置く。
            // 間に中断点を挟むと、その分だけ載せただけの段階が提示中として扱われる隙間が開く。
            guard !Task.isCancelled,
                  self.containerState == .attached,
                  !self.resultChannel.isResultSettled
            else {
                self.finishRemoval()
                return
            }
            self.containerState = .presenting
            await self.transitionRunner.runPresentationPhase {
                self.contentView.alpha = self.contentInitialAlpha
            }
            guard self.containerState == .presenting else { return }
            self.containerState = .shown
            if self.resultChannel.isResultSettled {
                // 提示の最中に来ていた閉鎖信号は、提示を完走させてからここで直列に扱う。
                self.beginDismissal()
            }
        }
    }

    /// 退出の演出と覆いの消滅フェードを並行して走らせ、両方の完了を待ってから撤去する。
    private func beginDismissal() {
        guard containerState == .presenting || containerState == .shown else { return }
        containerState = .dismissing
        // 退出中は覆いも中身も操作を受け付けない。
        view.isUserInteractionEnabled = false
        lifecycleTask?.cancel()
        lifecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.transitionRunner.runDismissalPhase()
            guard self.containerState == .dismissing else { return }
            self.finishRemoval()
        }
    }

    /// 器の撤去を提示層へ要求する。
    ///
    /// 要求を出したあと **器が実際に画面から外れ終わった通知**を受けてから中身の解放と配送へ進む。
    /// 結果を受けて次のダイアログを出す流れで、前のダイアログがまだ画面に残っている状態を作らないため。
    /// 撤去が完了するまでは退出中のままで、`removed` になるのは `completeRemoval()` の時点。
    /// - Parameter waitsForHostRemoval: 撤去の完了通知を待つか。器が既に画面を失っている経路では
    ///   待つ相手がいないので false にして即座に先へ進む (core/ADR-0017)
    private func finishRemoval(waitsForHostRemoval: Bool = true) {
        guard !isRemovalRequested else { return }
        isRemovalRequested = true
        let runningLifecycle = lifecycleTask
        lifecycleTask = nil
        runningLifecycle?.cancel()
        let dismissRequest = onDismissRequest
        onDismissRequest = nil
        guard let dismissRequest else {
            completeRemoval()
            return
        }
        guard waitsForHostRemoval else {
            // 撤去の要求だけ出し、完了を待たずに後始末と配送へ進む。
            dismissRequest {}
            completeRemoval()
            return
        }
        // ここだけ weak にする。提示面が完了通知を握りつぶしたときに、この閉包が器を
        // 永久に生かし続けないようにするため。器が先に解放されても配送は `outcomeDelivery`
        // (deinit で引き継ぐ) が担うので、呼び出し元が取り残されることはない。
        // 強保持へ揃えると、握りつぶされた completion が器の寿命を無限に伸ばす。
        dismissRequest { [weak self] in
            self?.completeRemoval()
        }
    }

    /// 撤去が終わったあとの後始末と配送。撤去の通知が重なっても1回しか進まない。
    /// ここで初めて `removed` になる (器を撤去し、確定済みの結果を配送した段階)。
    private func completeRemoval() {
        guard !didCompleteRemoval else { return }
        didCompleteRemoval = true
        containerState = .removed
        releaseContentHost()
        // ここまで来て未確定なのは器が画面を失った経路だけなので、その扱いで確定させて配送する。
        outcomeDelivery.submitLatchedOutcome()
    }

    /// 呼び出し元が待つのをやめたときの扱い (core/ADR-0017 の脱出口)。
    func handleCallerCancellation() {
        switch containerState {
        case .created:
            // まだ画面に載っていない。載った時点で演出なしの撤去に入る。
            break
        case .attached:
            finishRemoval()
        case .presenting:
            // 出現の演出の完走を待たず、退出へ進む。
            beginDismissal()
        case .shown:
            beginDismissal()
        case .dismissing:
            // 退出の演出の完了を待つのをやめ、そのまま撤去する。
            finishRemoval()
        case .removed:
            break
        }
    }

    /// 結果が確定したときの扱い。
    ///
    /// 器が画面を失った経路と呼び出し元の取り消しは、確定と同時に届く専用の扱いが受け持つ。
    /// 取り消しをここでも扱うと「この取り消しで退出に入った」のか「もともと退出中だった」のかを
    /// 見分けられなくなり、脱出口の判定 (core/ADR-0017) が狂う。
    private func handleSettled() {
        let origin = resultChannel.resultOrigin
        guard origin != .hostLost, origin != .callerCancellation else { return }
        switch containerState {
        case .created, .presenting, .dismissing, .removed:
            // 提示前は載った時点で、提示中は完走したあとで扱う。退出中と撤去後は何も起こさない。
            break
        case .attached:
            finishRemoval()
        case .shown:
            beginDismissal()
        }
    }

    /// 器が画面を失ったときの扱い。演出は成立しないので、実行中のフックを捨てて撤去する。
    /// 自分から撤去を要求済みなら、その撤去の完了通知が後始末を受け持つのでここでは何もしない。
    func handleHostLost() {
        guard !isRemovalRequested else { return }
        lifecycleTask?.cancel()
        resultChannel.settle(.cancelled, origin: .hostLost)
        // 器は既に提示の連なりから外れているため、撤去の完了を待つ相手がいない。
        finishRemoval(waitsForHostRemoval: false)
    }

    /// 結果チャネルの確定と取り消しをこの器へ結び付ける。
    func observeResultChannel() {
        resultChannel.onSettle { [weak self] _ in
            Task { @MainActor in
                self?.handleSettled()
            }
        }
        resultChannel.onCallerCancellation { [weak self] in
            Task { @MainActor in
                self?.handleCallerCancellation()
            }
        }
    }

    /// 中身のホストを child containment から外して解放する。
    ///
    /// ダイアログが閉じる全経路 (完了 / キャンセル / 呼び出し元キャンセル / 画面破棄) は
    /// 器の撤去で合流するため、ここが唯一の解放点になる。
    /// 器そのものが先に解放される経路では、child の保持ごと解放される。
    private func releaseContentHost() {
        guard let contentHost else { return }
        self.contentHost = nil
        contentHost.willMove(toParent: nil)
        contentHost.view.removeFromSuperview()
        contentHost.removeFromParent()
    }

    /// 外側タップを受け取ったときの扱い。
    ///
    /// スナップショット時点の `isCanceledOnTouchOutside` が true (既定) なら
    /// キャンセル操作と同じ経路で結果を確定させ、false なら何も起こさない。
    /// false のときもタップは覆いが吸収するため背後の画面へは透過しない。
    /// 退出中と撤去を要求したあとは入力を受け付けない。
    func reportOutsideTap() {
        guard containerState != .dismissing, !isRemovalRequested else { return }
        guard layout.isCanceledOnTouchOutside else { return }
        resultChannel.settle(.cancelled, origin: .outsideTap)
    }

    @objc
    private func handleBackdropTap() {
        reportOutsideTap()
    }

    /// 触れた View が外側タップにあたるかの判別。
    /// 中身の View とその子孫の上のタップは外側ではない。
    /// タップの受け手が分からない場合は覆いへのタップとして扱う。
    func isOutsideTap(touching touchedView: UIView?) -> Bool {
        guard let touchedView else { return true }
        return !touchedView.isDescendant(of: contentView)
    }
}

extension DialogContainerViewController: UIGestureRecognizerDelegate {
    /// 中身の View の上のタップは外側タップとして扱わない。
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        isOutsideTap(touching: touch.view)
    }
}
#endif
