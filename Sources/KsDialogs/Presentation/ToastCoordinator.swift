#if canImport(UIKit)
import Foundation
import UIKit
import os

/// 1 OS プロセス内で唯一の Toast の状態の正 (core/ADR-0030)。
///
/// 表示中の Toast のリスト (起動順)・各表示の器・各表示の消滅の期限を保持し、
/// 既定シングルトンも DI 注入したインスタンスも、すべての入口がここへ委譲する。
/// これにより入口をまたいだ利用でも、重なり順と消滅の管理が1か所にまとまる。
///
/// 受理は任意のスレッドから行え、UI スレッド上で受理順に直列化される。
/// 構成ミス (未登録の ViewModel 型) だけは受理そのものの失敗として呼び出し元へ返し、
/// それ以降の失敗は表示1枚の破棄に留める (表示は fire-and-forget なので返せない — core/ADR-0031)。
@MainActor
final class ToastCoordinator {
    /// 既定の入口が共有する唯一の coordinator。
    nonisolated static let shared = ToastCoordinator()

    /// 表示にまつわる不具合を知らせるための記録口。
    private nonisolated static let logger = Logger(subsystem: "jp.kamusoft.ksdialogs", category: "toast")

    /// カスタム Toast の登録。
    nonisolated let registry: ToastViewRegistry

    /// 一括設定。
    nonisolated let settings: ToastSettings

    /// 受理を UI スレッド上で起動順に直列化する待ち行列。
    nonisolated let acceptanceQueue = ToastAcceptanceQueue()

    private let presentationSurface: any ToastPresentationSurface

    private let announcer: any ToastAccessibilityAnnouncer

    /// 表示中の Toast。並びがそのまま起動順で、後ろほど手前に重なる。
    private var displays: [ToastDisplay] = []

    /// 取り付け先の出現を待つ間だけ張る、提示先の出現の合図の購読。
    private var hostAppearanceRegistration: DialogHostAppearanceRegistration?

    /// 期限を決めずに待っている表示がある間だけ張る、前面を離れた合図の購読。
    private var foregroundDepartureRegistration: DialogHostAppearanceRegistration?

    nonisolated init(
        registry: ToastViewRegistry = .shared,
        settings: ToastSettings = ToastSettings(),
        presentationSurface: any ToastPresentationSurface = KeyWindowToastPresentationSurface(),
        announcer: any ToastAccessibilityAnnouncer = SystemToastAccessibilityAnnouncer()
    ) {
        self.registry = registry
        self.settings = settings
        self.presentationSurface = presentationSurface
        self.announcer = announcer
    }

    isolated deinit {
        hostAppearanceRegistration?.cancel()
        foregroundDepartureRegistration?.cancel()
    }

    // MARK: - 観察 (テストと内部からの読み取り)

    /// 表示中の Toast の枚数 (取り付け先待ちのものを含む)。
    var displayCount: Int {
        displays.count
    }

    /// 取り付け済みの器。並びは起動順。
    var presentedContainers: [ToastContainerViewController] {
        displays.compactMap(\.container)
    }

    /// 取り付け済みの器に載っている中身の View。並びは起動順。
    var presentedContentViews: [UIView] {
        presentedContainers.map(\.contentView)
    }

    /// 何かが表示されているか。
    var isPresenting: Bool {
        !presentedContainers.isEmpty
    }

    // MARK: - 受理

    /// 表示1枚を受理する。戻り値は持たず、表示の終了も待たない (core/ADR-0031)。
    ///
    /// 登録経路で ViewModel 型が未登録なら、ここで同期に失敗して表示は行われない。
    /// - Parameters:
    ///   - request: 表示する中身の指定
    ///   - duration: 表示するミリ秒。nil なら `ToastStyle` の既定 duration
    ///   - placement: 配置。nil なら添付・style のアプリ既定配置・契約既定値の順に委ねる
    nonisolated func accept(
        _ request: ToastContentRequest,
        duration: Int?,
        placement: DialogPlacement?
    ) throws {
        // View factory の登録は受理の時点で解決し、取り付けの時点では引き直さない。
        let request = try resolveFactoryIfNeeded(request)
        let style = settings.style
        let durationMilliseconds = Self.effectiveDuration(duration, style: style)
        // 受理の時刻はここで記録する。そこから数えるかどうかは、UI スレッドの開始処理の時点の状態で決める。
        let acceptedAt = ContinuousClock.now
        let fallbackPlacement = style.defaultPlacement ?? ToastPlacementDefault.placement
        acceptanceQueue.enqueue { [self] in
            beginDisplay(
                request,
                style: style,
                placement: placement,
                fallbackPlacement: fallbackPlacement,
                acceptedAt: acceptedAt,
                duration: .milliseconds(durationMilliseconds)
            )
        }
    }

    /// 有効な duration (ミリ秒) を決める。
    /// 0 以下の引数は style の既定へ、style の既定自体が 0 以下なら内蔵既定へ丸め、警告を残す。
    nonisolated static func effectiveDuration(_ duration: Int?, style: ToastStyle) -> Int {
        if let duration {
            if duration > 0 { return duration }
            logger.warning("Toast duration must be a positive integer. Showing with the default duration.")
        }
        if style.defaultDuration > 0 { return style.defaultDuration }
        logger.warning("The default duration of ToastStyle is not a positive integer. Showing with the built-in default.")
        return ToastStyle.builtinDefaultDuration
    }

    // MARK: - 表示の出し入れ

    /// 受理した1枚を表示リストに載せ、取り付けと期限の計時を始める。
    ///
    /// 中身はここでは作らず、取り付けの時点で作る (`attachIfPossible`、core/ADR-0042)。
    ///
    /// アプリが前面にいるのに取り付け先が無ければ (前面の待ち)、期限を決めずに待たせ、取り付けた時点から
    /// 数える (core/ADR-0043)。起動の途中や割り込みの最中に表示時間を使い切らないようにするため。
    /// それ以外は受理の時点から実時間で数える (アプリが背面にある間も進む)。
    /// 判定は前面・取り付け先の状態が変わるのと同じ UI スレッドの手番で行い、判定と載せる処理を食い違わせない。
    private func beginDisplay(
        _ request: ToastContentRequest,
        style: ToastStyle,
        placement: DialogPlacement?,
        fallbackPlacement: DialogPlacement,
        acceptedAt: ContinuousClock.Instant,
        duration: Duration
    ) {
        let display = ToastDisplay(
            request: request,
            style: style,
            showPlacement: placement,
            fallbackPlacement: fallbackPlacement,
            acceptedAt: acceptedAt,
            duration: duration
        )
        let isForegroundWait = presentationSurface.hostView == nil && presentationSurface.isAppInForeground
        if !isForegroundWait {
            display.fixDeadline(startingAt: acceptedAt)
        }
        guard !display.hasReachedDeadline() else {
            // 受理から MainActor へ届くまでの遅れだけで期限を越えた表示。
            // 中身も器も作らずに捨てる (満了した表示は表示されない)。
            return
        }
        displays.append(display)
        attachIfPossible(display)
        startDeadlineTimer(display)
    }

    /// 期限の決まった表示について、期限を待つ仕事を始める。
    ///
    /// 期限が未確定の表示・既に待ち始めた表示・破棄された表示 (中身の生成の失敗) では何もしない。
    private func startDeadlineTimer(_ display: ToastDisplay) {
        guard let deadline = display.deadline,
              display.timerTask == nil,
              !display.isFinishing else { return }
        display.timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            await self?.finish(display)
        }
    }

    /// まだ期限の無い表示について、`start` から数えた期限を決め、待ち始める。
    private func fixDeadlineAndStartTimer(_ display: ToastDisplay, startingAt start: ContinuousClock.Instant) {
        guard display.fixDeadline(startingAt: start) else { return }
        startDeadlineTimer(display)
    }

    /// 取り付け先があれば中身と器を作って重ねる。
    ///
    /// 取り付け先が無いときは中身を作らずに表示を保留し、提示先の出現を待つ。
    /// 期限の決まった表示は待つ間も時間が進むため、現れないまま期限が来た表示は、中身を作らずに破棄される
    /// (型指定経路の ViewModel の生成と configure も走らない)。
    /// 期限の確認はここでも行う — 取り付け先の復帰が期限のタイマーより先に走っても、
    /// 満了した表示を一瞬見せないようにする。
    /// 期限を決めずに待っている表示は、前面を離れた合図も待ち、取り付けた時点から数え始める (core/ADR-0043)。
    ///
    /// 中身の実体化に失敗したら、その1枚だけを破棄して資源を解放する。
    /// 他の表示には影響せず、呼び出し元へも返さない (既に戻っているため)。
    private func attachIfPossible(_ display: ToastDisplay) {
        guard display.container == nil, !display.isFinishing else { return }
        guard !display.hasReachedDeadline() else {
            discard(display)
            return
        }
        guard let hostView = presentationSurface.hostView else {
            startWaitingForHost()
            if display.deadline == nil {
                startWaitingForForegroundDeparture()
            }
            return
        }
        let resolved: ToastResolvedContent
        do {
            resolved = try makeContent(for: display.request, style: display.style)
        } catch {
            Self.logger.warning(
                "Could not create the Toast content. This presentation is discarded: \(error.localizedDescription, privacy: .public)"
            )
            discard(display)
            return
        }
        display.viewModel = resolved.viewModel
        let container = ToastContainerViewController(
            content: resolved.content,
            placement: display.showPlacement,
            fallbackPlacement: display.fallbackPlacement
        )
        display.container = container
        // Loading が同じ取り付け先に載っているときは、その下へ入れて常に Loading を前面に保つ。
        container.attach(to: hostView, below: Self.lowestLoadingView(in: hostView))
        // 画面が利用者に見えた時点から数える。既に期限の決まった表示では何も変わらない。
        fixDeadlineAndStartTimer(display, startingAt: .now)
    }

    /// 取り付け先に載っている Loading の器のうち、最も奥にある View。
    private static func lowestLoadingView(in hostView: UIView) -> UIView? {
        hostView.subviews.first { $0 is LoadingContainerRootView }
    }

    /// 出の演出と撤去を進め、表示リストから外す。期限の到達で呼ばれる。
    private func finish(_ display: ToastDisplay) async {
        guard !display.isFinishing else { return }
        display.isFinishing = true
        if let container = display.container {
            await container.dismiss()
        }
        display.releaseResources()
        displays.removeAll { $0 === display }
        stopWaitingIfSatisfied()
    }

    /// 表示中のすべての Toast を、演出も期限も待たずに捨てる。
    ///
    /// 公開の入口からは呼ばれない。検証の後始末で、器だけでなく表示と期限の計時も残さないために使う
    /// (期限まで表示が残ると、中身と ViewModel を握り続けるため)。期限による撤去が進行中の表示と
    /// 重なっても、撤去は 1 回分しか効かない。
    func discardAll() {
        for display in displays {
            discard(display)
        }
    }

    /// 表示を成立しなかったものとして捨てる。演出は走らせない。
    /// 器が取り付いていれば、その場で取り付け先から外す。
    private func discard(_ display: ToastDisplay) {
        display.isFinishing = true
        display.timerTask?.cancel()
        display.container?.removeImmediately()
        display.releaseResources()
        displays.removeAll { $0 === display }
        stopWaitingIfSatisfied()
    }

    // MARK: - 取り付け先の出現待ち

    /// 取り付け先が現れるのを待ち始める。既に待っていれば何もしない。
    private func startWaitingForHost() {
        guard hostAppearanceRegistration == nil else { return }
        hostAppearanceRegistration = presentationSurface.observeHostAppearance { [weak self] in
            self?.attachPendingDisplays()
        }
    }

    /// 保留中の表示を取り付け直す。提示先の出現の合図で呼ばれる。
    ///
    /// 合図は「現れたかもしれない」ことだけを知らせるので、取り付け先が無ければ待ち続ける。
    private func attachPendingDisplays() {
        for display in displays where display.container == nil {
            attachIfPossible(display)
        }
        stopWaitingIfSatisfied()
    }

    /// 前面を離れた合図を待ち始める。既に待っていれば何もしない。
    private func startWaitingForForegroundDeparture() {
        guard foregroundDepartureRegistration == nil else { return }
        foregroundDepartureRegistration = presentationSurface.observeForegroundDeparture { [weak self] in
            self?.fixDeadlinesOnForegroundDeparture()
        }
    }

    /// 期限を決めずに待っていた表示の期限を、前面を離れた時点から数えて決める。
    ///
    /// 取り付け先に載らないまま背面へ下がった表示は、背面の表示と同じく実時間で数え始める
    /// (core/ADR-0043)。その期限の前に取り付け先が現れれば、その期限まで表示する。
    private func fixDeadlinesOnForegroundDeparture() {
        let now = ContinuousClock.now
        for display in displays {
            fixDeadlineAndStartTimer(display, startingAt: now)
        }
        stopWaitingIfSatisfied()
    }

    /// 待つ理由の無くなった購読を解除する。
    ///
    /// 提示先の出現の合図は、取り付け先を待つ表示がある間だけ張る。
    /// 前面を離れた合図は、期限を決めずに待つ表示がある間だけ張る。
    private func stopWaitingIfSatisfied() {
        if let hostAppearanceRegistration,
           !displays.contains(where: { $0.container == nil }) {
            hostAppearanceRegistration.cancel()
            self.hostAppearanceRegistration = nil
        }
        if let foregroundDepartureRegistration,
           !displays.contains(where: { $0.deadline == nil }) {
            foregroundDepartureRegistration.cancel()
            self.foregroundDepartureRegistration = nil
        }
    }

    // MARK: - 中身の解決

    /// 解決した中身と、器が撤去まで保持する参照。
    private struct ToastResolvedContent {
        let content: DialogContent
        let viewModel: AnyObject?
    }

    private func makeContent(
        for request: ToastContentRequest,
        style: ToastStyle
    ) throws -> ToastResolvedContent {
        switch request {
        case .builtin(let message):
            let contentView = ToastDefaultContentView(
                message: message,
                style: style,
                announcer: announcer
            )
            return ToastResolvedContent(content: DialogContent(view: contentView), viewModel: nil)
        case .registered(let viewModel):
            return try makeCustomContent(viewModel: viewModel, factory: resolveFactory(for: viewModel))
        case .inline(let viewModel, let factory), .resolved(let viewModel, let factory):
            // 受け取った factory をそのまま使う。ここでレジストリは読まないので、インライン経路では
            // 登録の有無が表示にも登録内容にも影響せず (core/ADR-0013)、登録経路では受理の時点の登録で作る。
            return try makeCustomContent(viewModel: viewModel, factory: factory)
        case .typed(let prepare, let factory):
            // ViewModel の生成と configure はここ (UI スレッド上の取り付けの時点) で行う。
            // 解決は受理の時点で終わっているため、レジストリは引き直さない。
            return try makeCustomContent(viewModel: prepare(), factory: factory)
        }
    }

    /// カスタム Toast の中身を factory から作る。
    private func makeCustomContent(
        viewModel: any ToastViewModel,
        factory: ToastViewFactory
    ) throws -> ToastResolvedContent {
        guard let content = try factory.makeContent(viewModel) else {
            throw DialogError.viewFactoryTypeMismatch(
                viewModelType: String(describing: type(of: viewModel))
            )
        }
        return ToastResolvedContent(content: content, viewModel: viewModel)
    }

    /// レジストリ経由の指定を、解決済みの factory を持つ指定に置き換える。
    /// 未登録の ViewModel 型はここで失敗する。それ以外の指定はそのまま返す。
    private nonisolated func resolveFactoryIfNeeded(_ request: ToastContentRequest) throws -> ToastContentRequest {
        guard case .registered(let viewModel) = request else { return request }
        return .resolved(viewModel: viewModel, factory: try resolveFactory(for: viewModel))
    }

    private nonisolated func resolveFactory(for viewModel: any ToastViewModel) throws -> ToastViewFactory {
        let viewModelType = type(of: viewModel)
        guard let factory = registry.factory(forKey: DialogViewModelKey(viewModelType)) else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        return factory
    }
}
#endif
