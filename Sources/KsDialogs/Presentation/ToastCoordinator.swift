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

    /// 取り付け先の出現を待つ間だけ立てる見張り。
    private var hostObserver: (any NSObjectProtocol)?

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
        if let hostObserver {
            NotificationCenter.default.removeObserver(hostObserver)
        }
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
        if case .registered(let viewModel) = request {
            _ = try resolveFactory(for: viewModel)
        }
        let style = settings.style
        let durationMilliseconds = Self.effectiveDuration(duration, style: style)
        // 計時は受理時点から始まり、実時間で消費する (アプリが背面にある間も進む)。
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(durationMilliseconds))
        let fallbackPlacement = style.defaultPlacement ?? ToastPlacementDefault.placement
        acceptanceQueue.enqueue { [self] in
            beginDisplay(
                request,
                style: style,
                placement: placement,
                fallbackPlacement: fallbackPlacement,
                deadline: deadline
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

    /// 受理した1枚を組み立てて表示に載せる。
    ///
    /// 中身の実体化に失敗したら、その1枚だけを破棄して資源を解放する。
    /// 他の表示には影響せず、呼び出し元へも返さない (既に戻っているため)。
    private func beginDisplay(
        _ request: ToastContentRequest,
        style: ToastStyle,
        placement: DialogPlacement?,
        fallbackPlacement: DialogPlacement,
        deadline: ContinuousClock.Instant
    ) {
        guard ContinuousClock.now < deadline else {
            // 受理から MainActor へ届くまでの遅れだけで期限を越えた表示。
            // 中身も器も作らずに捨てる (満了した表示は表示されない)。
            return
        }
        let resolved: ToastResolvedContent
        do {
            resolved = try makeContent(for: request, style: style)
        } catch {
            Self.logger.warning(
                "Could not create the Toast content. This presentation is discarded: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        let display = ToastDisplay(
            content: resolved.content,
            viewModel: resolved.viewModel,
            showPlacement: placement,
            fallbackPlacement: fallbackPlacement,
            deadline: deadline
        )
        displays.append(display)
        attachIfPossible(display)
        display.timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            await self?.finish(display)
        }
    }

    /// 取り付け先があれば器を作って重ねる。
    ///
    /// 取り付け先が無いときは表示を保留し、提示先の出現を待つ。
    /// 計時は受理時点から進んでいるため、現れないまま期限が来た表示は表示されずに破棄される。
    /// 期限の確認はここでも行う — 取り付け先の復帰が期限のタイマーより先に走っても、
    /// 満了した表示を一瞬見せないようにする。
    private func attachIfPossible(_ display: ToastDisplay) {
        guard display.container == nil, !display.isFinishing else { return }
        guard ContinuousClock.now < display.deadline else {
            discard(display)
            return
        }
        guard let hostView = presentationSurface.hostView else {
            startWaitingForHost()
            return
        }
        let container = ToastContainerViewController(
            content: display.content,
            placement: display.showPlacement,
            fallbackPlacement: display.fallbackPlacement
        )
        display.container = container
        // Loading が同じ取り付け先に載っているときは、その下へ入れて常に Loading を前面に保つ。
        container.attach(to: hostView, below: Self.lowestLoadingView(in: hostView))
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
        stopWaitingForHostIfSatisfied()
    }

    /// 表示を成立しなかったものとして捨てる。演出は走らせない。
    private func discard(_ display: ToastDisplay) {
        display.isFinishing = true
        display.timerTask?.cancel()
        display.releaseResources()
        displays.removeAll { $0 === display }
        stopWaitingForHostIfSatisfied()
    }

    // MARK: - 取り付け先の出現待ち

    /// 取り付け先が現れるのを待ち始める。既に待っていれば何もしない。
    private func startWaitingForHost() {
        guard hostObserver == nil else { return }
        hostObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.attachPendingDisplays()
            }
        }
    }

    /// 保留中の表示を取り付け直す。
    func attachPendingDisplays() {
        for display in displays where display.container == nil {
            attachIfPossible(display)
        }
        stopWaitingForHostIfSatisfied()
    }

    /// 保留中の表示が無くなったら見張りを畳む。
    private func stopWaitingForHostIfSatisfied() {
        guard let hostObserver, !displays.contains(where: { $0.container == nil }) else { return }
        NotificationCenter.default.removeObserver(hostObserver)
        self.hostObserver = nil
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
        case .inline(let viewModel, let factory):
            // レジストリは読まないので、登録の有無は表示にも登録内容にも影響しない (core/ADR-0013)。
            return try makeCustomContent(viewModel: viewModel, factory: factory)
        case .typed(let prepare, let factory):
            // ViewModel の生成と configure はここ (UI スレッド上の受理順) で行う。
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

    private nonisolated func resolveFactory(for viewModel: any ToastViewModel) throws -> ToastViewFactory {
        let viewModelType = type(of: viewModel)
        guard let factory = registry.factory(forKey: DialogViewModelKey(viewModelType)) else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        return factory
    }
}
#endif
