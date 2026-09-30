#if canImport(UIKit)
import UIKit
import os

/// 表示に使う中身の指定。
enum LoadingContentRequest {
    /// ライブラリ同梱の内蔵コンテンツ (既定ローディング)。
    case builtin
    /// レジストリに登録済みの ViewModel から作るカスタム Loading View。
    case registered(viewModel: any LoadingViewModel)
    /// レジストリを経由せず、その場で渡された factory から作るカスタム Loading View。
    case inline(viewModel: any LoadingViewModel, factory: LoadingViewFactory)
    /// 呼び出し時点でレジストリから解決済みの factory と ViewModel から作るカスタム Loading View
    /// (型指定 show / start。core/ADR-0035。登録経路も開始の時点でこの形に解決してから控える)。
    ///
    /// 解決を呼び出し時点で終えているため、状態の正に届くまでの間に再登録が起きても
    /// 最初に取得した組で中身を作る。
    case resolved(viewModel: any LoadingViewModel, factory: LoadingViewFactory)
}

/// 合流1件の身分証。開始した表示世代を持ち、終了・報告がその世代のものかを見分ける。
struct LoadingUseToken: Sendable {
    let generation: Int
}

/// 1 OS プロセス内で唯一の Loading の状態の正 (core/ADR-0024・core/ADR-0027)。
///
/// 合流カウント・表示世代・表示中のコンテンツ・最新のメッセージと進捗を保持し、
/// 既定シングルトンも DI 注入したインスタンスも、すべての入口がここへ委譲する。
/// これにより入口をまたいだ利用でも表示は1つに合流する。
///
/// 状態を変える操作はすべて UI スレッド上で受理順に直列化され、「最新 (後勝ち)」は受理順で定まる。
@MainActor
final class LoadingCoordinator {
    /// 既定の入口が共有する唯一の coordinator。
    nonisolated static let shared = LoadingCoordinator()

    /// カスタム Loading の登録。
    nonisolated let registry: LoadingViewRegistry

    /// スタイルと既定ローディングの器メタ属性。
    nonisolated let settings: LoadingSettings

    private let presentationSurface: any LoadingPresentationSurface

    /// 表示世代。新しい表示の開始と `hide()` で進み、旧世代の終了・報告を締め出す。
    private var generation = 0

    /// 現在の世代に合流している利用の数。
    private var activeCount = 0

    /// 表示中の器。取り付け先が現れるまでは nil のままになる。
    private var container: LoadingContainerViewController?

    /// 提示先が無いまま始まった表示の中身の指定。提示先が現れた時点でここから中身を作る。
    private var pendingDisplay: LoadingPendingDisplay?

    /// 提示先の出現を待つ間だけ張る、提示先の出現の合図の購読。
    private var hostAppearanceRegistration: DialogHostAppearanceRegistration?

    /// 表示にまつわる不具合を知らせる記録口。
    private let warningLog: @MainActor @Sendable (String) -> Void

    /// 表示中の内蔵コンテンツ。カスタム View 表示中は nil。
    private var builtinContentView: LoadingDefaultContentView?

    /// 表示中のカスタム View の ViewModel。既定ローディング表示中は nil。
    private var customViewModel: AnyObject?

    /// この表示の開始時に読んだスタイル。表示中の設定変更には追随しない。
    private var displayedStyle = LoadingStyle()

    /// 最新のメッセージ (後勝ち)。
    private var latestMessage: String?

    /// 最新の進捗 (後勝ち)。未報告なら nil。
    private var latestProgress: Double?

    /// 進行中の撤去。新しい開始はこの完了を待ってから新世代として始まる。
    private var dismissalTask: Task<Void, Never>?

    /// - Parameters:
    ///   - warningLog: 警告の記録口。既定は OS のログへ警告として残す
    nonisolated init(
        registry: LoadingViewRegistry = .shared,
        settings: LoadingSettings = LoadingSettings(),
        presentationSurface: any LoadingPresentationSurface = KeyWindowLoadingPresentationSurface(),
        warningLog: @escaping @MainActor @Sendable (String) -> Void = LoadingCoordinator.logWarning
    ) {
        self.registry = registry
        self.settings = settings
        self.presentationSurface = presentationSurface
        self.warningLog = warningLog
    }

    isolated deinit {
        hostAppearanceRegistration?.cancel()
    }

    /// OS のログの記録口。
    private nonisolated static let logger = Logger(subsystem: "jp.kamusoft.ksdialogs", category: "loading")

    /// 警告を OS のログへ残す既定の記録口。
    nonisolated static func logWarning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    // MARK: - 観察 (テストと内部からの読み取り)

    /// 器が取り付いているか。
    var isPresenting: Bool {
        container != nil && dismissalTask == nil
    }

    /// 提示先の出現を待っている表示があるか。
    var isWaitingForHost: Bool {
        pendingDisplay != nil
    }

    /// 出の演出と撤去が進行中か。
    var isDismissing: Bool {
        dismissalTask != nil
    }

    /// 現在の合流数。
    var coalescedUseCount: Int {
        activeCount
    }

    /// 表示中の中身の View。
    var presentedContentView: UIView? {
        container?.contentView
    }

    /// 表示中の内蔵コンテンツ。
    var presentedBuiltinContentView: LoadingDefaultContentView? {
        builtinContentView
    }

    /// 表示中の器。
    var presentedContainer: LoadingContainerViewController? {
        container
    }

    // MARK: - 合流の受理

    /// 合流1件を開始する。
    ///
    /// 出の演出の途中なら、その撤去の完了を待ってから新しい世代として始める。
    /// 構成ミス (未登録の ViewModel 型) はここで失敗するため、呼び出し元は処理を実行しない。
    ///
    /// 提示先があれば中身をここで作り、その失敗も開始の失敗になる。
    /// 提示先が無ければ中身の指定だけを控えて提示先の出現を待つ (中身は現れた時点で作る)。
    /// どちらの場合も View factory の解決はここで行うので、未登録は提示先の有無によらず開始の失敗になる。
    func beginUse(
        _ request: LoadingContentRequest,
        message: String?,
        placement: DialogPlacement?
    ) async throws -> LoadingUseToken {
        await waitForPendingDismissal()
        guard activeCount > 0 else {
            // 新しい世代。構成ミスと、提示先があるときの中身の生成の失敗は、開始そのものの失敗になる。
            let style = settings.style
            let resolvedRequest = try resolveFactoryIfNeeded(request)
            let hostView = presentationSurface.hostView
            var resolved: LoadingResolvedContent?
            if hostView != nil {
                resolved = try makeContent(for: resolvedRequest, style: style)
            }
            generation += 1
            activeCount = 1
            displayedStyle = style
            latestMessage = message
            latestProgress = nil
            if let hostView, let resolved {
                startDisplay(resolved, placement: placement, on: hostView)
            } else {
                waitForHost(LoadingPendingDisplay(request: resolvedRequest, placement: placement))
            }
            return LoadingUseToken(generation: generation)
        }
        // 合流。コンテンツは最初の開始のものを維持するが、構成ミスは同じように弾く。
        try validateContentRequest(request)
        activeCount += 1
        if let message {
            latestMessage = message
            refreshBuiltinText()
        }
        return LoadingUseToken(generation: generation)
    }

    /// 出の演出の途中なら、その撤去の完了まで待つ。
    /// 待っている間に別の撤去が始まっていたらもう一度待つ。
    private func waitForPendingDismissal() async {
        while let dismissalTask {
            await dismissalTask.value
        }
    }

    /// 合流1件を終了する。旧世代の終了は現在の表示に影響しない。
    /// 合流最後の1件なら器の撤去まで待ってから戻る。
    func endUse(_ token: LoadingUseToken) async {
        guard token.generation == generation, activeCount > 0 else { return }
        activeCount -= 1
        guard activeCount == 0 else { return }
        await finishDisplay()
    }

    /// 合流数によらず表示を閉じる。走行中の処理には干渉しない。
    func hide() async {
        guard activeCount > 0 || container != nil || dismissalTask != nil else { return }
        // 走行中の利用が持つ身分証を旧世代にして、以後の終了・報告を締め出す。
        generation += 1
        activeCount = 0
        await finishDisplay()
    }

    /// 表示中のメッセージを更新する。合流には関与しない。
    /// 提示先を待っている既定ローディングでも受け付け、表示の時点で反映する。
    func setMessage(_ message: String?) {
        guard activeCount > 0,
              builtinContentView != nil || pendingDisplay?.isBuiltin == true else { return }
        latestMessage = message
        refreshBuiltinText()
    }

    /// 進捗の報告を受理する。旧世代の報告は捨てる。
    func report(progress: Double, token: LoadingUseToken) {
        guard token.generation == generation, activeCount > 0 else { return }
        // 非有限値は報告そのものを無視し、直前の表示を保つ。
        guard progress.isFinite else { return }
        let clamped = min(max(progress, 0), 1)
        latestProgress = clamped
        refreshBuiltinText()
        (customViewModel as? any LoadingProgressReceiver)?.onProgress(clamped)
    }

    // MARK: - 表示の出し入れ

    /// 解決済みの中身から器を組み立てて取り付ける。器は取り付いた時点で入りの演出を始める。
    private func startDisplay(
        _ resolved: LoadingResolvedContent,
        placement: DialogPlacement?,
        on hostView: UIView
    ) {
        builtinContentView = resolved.builtinContentView
        customViewModel = resolved.viewModel
        refreshBuiltinText()
        let container = LoadingContainerViewController(content: resolved.content, placement: placement)
        self.container = container
        container.attach(to: hostView)
    }

    // MARK: - 提示先の出現待ち

    /// 提示先が無いまま始まった表示の中身の指定を控え、提示先の出現を待ち始める。
    ///
    /// 表示は成立していないが合流状態は成立しており、呼び出し元の処理は通常どおり実行される
    /// (提示環境の不在は構成ミスではない)。ViewModel は進捗の受け口としてここで控えるので、
    /// 表示の前に報告された進捗も ViewModel へ届く。
    private func waitForHost(_ pending: LoadingPendingDisplay) {
        pendingDisplay = pending
        customViewModel = pending.viewModel
        guard hostAppearanceRegistration == nil else { return }
        hostAppearanceRegistration = presentationSurface.observeHostAppearance { [weak self] in
            self?.presentPendingDisplayIfHostAppeared()
        }
    }

    /// 提示先の出現の合図を受けて、待っている表示を出す。
    ///
    /// 合図は「現れたかもしれない」ことだけを知らせるので、提示先が無ければ待ち続ける。
    /// 現れていれば中身を作り、入りの演出から表示する。ここは既に走り出した処理の途中なので、
    /// 中身の生成の失敗は呼び出し元へ返さず、警告を残してこの表示を諦める
    /// (合流状態は残り、処理はそのまま完了できる)。生成できない中身を次の合図で作り直しても
    /// 同じ失敗を繰り返すため、待ちもここでやめる (core/ADR-0042)。
    private func presentPendingDisplayIfHostAppeared() {
        guard let pending = pendingDisplay, activeCount > 0, container == nil, dismissalTask == nil else {
            return
        }
        guard let hostView = presentationSurface.hostView else { return }
        stopWaitingForHost()
        let resolved: LoadingResolvedContent
        do {
            resolved = try makeContent(for: pending.request, style: displayedStyle)
        } catch {
            warningLog("Could not create the Loading content. Nothing is presented: \(error.localizedDescription)")
            return
        }
        startDisplay(resolved, placement: pending.placement, on: hostView)
    }

    /// 待っている表示の中身の指定を捨て、提示先の出現の合図の購読を解除する。
    private func stopWaitingForHost() {
        pendingDisplay = nil
        hostAppearanceRegistration?.cancel()
        hostAppearanceRegistration = nil
    }

    /// 出の演出と撤去を進め、完了してから戻る。
    /// 撤去が既に進行中なら、その完了に合流する。
    private func finishDisplay() async {
        if let dismissalTask {
            await dismissalTask.value
            return
        }
        guard let container else {
            clearDisplayState()
            return
        }
        let task = Task { @MainActor in
            await container.dismiss()
            self.completeDismissal()
        }
        dismissalTask = task
        await task.value
    }

    /// 撤去の完了後の後始末。待っている呼び出しはこの後始末のあとに戻る。
    private func completeDismissal() {
        container = nil
        clearDisplayState()
        dismissalTask = nil
    }

    private func clearDisplayState() {
        stopWaitingForHost()
        builtinContentView = nil
        customViewModel = nil
        latestMessage = nil
        latestProgress = nil
    }

    /// 最新のメッセージと進捗から表示テキストを組み立て直す。
    /// フォーマット関数はこの UI スレッド上で呼ばれる。
    private func refreshBuiltinText() {
        guard let builtinContentView else { return }
        let message = latestMessage ?? displayedStyle.defaultMessage
        builtinContentView.apply(text: displayedStyle.progressFormat(message, latestProgress))
    }

    // MARK: - 中身の解決

    /// 解決した中身と、表示中の更新に使う参照。
    private struct LoadingResolvedContent {
        let content: DialogContent
        let builtinContentView: LoadingDefaultContentView?
        let viewModel: AnyObject?
    }

    /// 提示先の出現を待つ表示の、中身の指定と配置。
    private struct LoadingPendingDisplay {
        /// View factory の解決を済ませた中身の指定。
        let request: LoadingContentRequest
        let placement: DialogPlacement?

        /// 既定ローディングの表示か。
        var isBuiltin: Bool {
            if case .builtin = request { return true }
            return false
        }

        /// カスタム View の ViewModel。既定ローディングでは nil。
        var viewModel: AnyObject? {
            switch request {
            case .builtin:
                nil
            case .registered(let viewModel), .inline(let viewModel, _), .resolved(let viewModel, _):
                viewModel
            }
        }
    }

    /// レジストリ経由の指定を、解決済みの factory を持つ指定に置き換える。
    /// 未登録の ViewModel 型はここで失敗する。それ以外の指定はそのまま返す。
    private func resolveFactoryIfNeeded(_ request: LoadingContentRequest) throws -> LoadingContentRequest {
        guard case .registered(let viewModel) = request else { return request }
        return .resolved(viewModel: viewModel, factory: try resolveFactory(for: viewModel))
    }

    private func makeContent(
        for request: LoadingContentRequest,
        style: LoadingStyle
    ) throws -> LoadingResolvedContent {
        switch request {
        case .builtin:
            let contentView = LoadingDefaultContentView(style: style)
            // 既定ローディングには利用者が属性を添付する View が無いため、
            // 設定プロパティの値をこの内蔵コンテンツへの添付として載せる (core/ADR-0022)。
            contentView.ksDialogOptions = settings.options
            return LoadingResolvedContent(
                content: DialogContent(view: contentView),
                builtinContentView: contentView,
                viewModel: nil
            )
        case .registered(let viewModel):
            return try makeCustomContent(viewModel: viewModel, factory: resolveFactory(for: viewModel))
        case .inline(let viewModel, let factory), .resolved(let viewModel, let factory):
            // 受け取った factory をそのまま使う。ここでレジストリは読まないので、
            // インライン経路では登録の有無が表示に影響せず (core/ADR-0013)、
            // 型指定経路では呼び出し時点のスナップショットがそのまま使われる。
            return try makeCustomContent(viewModel: viewModel, factory: factory)
        }
    }

    /// カスタム Loading の中身を factory から作る。
    private func makeCustomContent(
        viewModel: any LoadingViewModel,
        factory: LoadingViewFactory
    ) throws -> LoadingResolvedContent {
        guard let content = try factory.makeContent(viewModel) else {
            throw DialogError.viewFactoryTypeMismatch(
                viewModelType: String(describing: type(of: viewModel))
            )
        }
        return LoadingResolvedContent(
            content: content,
            builtinContentView: nil,
            viewModel: viewModel
        )
    }

    /// 合流のときも構成ミスは同じように弾く (中身は作らない)。
    private func validateContentRequest(_ request: LoadingContentRequest) throws {
        guard case .registered(let viewModel) = request else { return }
        _ = try resolveFactory(for: viewModel)
    }

    private func resolveFactory(for viewModel: any LoadingViewModel) throws -> LoadingViewFactory {
        let viewModelType = type(of: viewModel)
        guard let factory = registry.factory(forKey: DialogViewModelKey(viewModelType)) else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        return factory
    }
}
#endif
