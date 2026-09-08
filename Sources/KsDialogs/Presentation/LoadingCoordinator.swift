#if canImport(UIKit)
import UIKit

/// 表示に使う中身の指定。
enum LoadingContentRequest {
    /// ライブラリ同梱の内蔵コンテンツ (既定ローディング)。
    case builtin
    /// レジストリに登録済みの ViewModel から作るカスタム Loading View。
    case registered(viewModel: any LoadingViewModel)
    /// レジストリを経由せず、その場で渡された factory から作るカスタム Loading View。
    case inline(viewModel: any LoadingViewModel, factory: LoadingViewFactory)
    /// 呼び出し時点でレジストリから解決済みの factory と、その場で生成された ViewModel から作る
    /// カスタム Loading View (型指定 show / start。core/ADR-0035)。
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

    /// 表示中の器。取り付け先が無いときは表示が成立しないので nil のままになる。
    private var container: LoadingContainerViewController?

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

    nonisolated init(
        registry: LoadingViewRegistry = .shared,
        settings: LoadingSettings = LoadingSettings(),
        presentationSurface: any LoadingPresentationSurface = KeyWindowLoadingPresentationSurface()
    ) {
        self.registry = registry
        self.settings = settings
        self.presentationSurface = presentationSurface
    }

    // MARK: - 観察 (テストと内部からの読み取り)

    /// 器が取り付いているか。
    var isPresenting: Bool {
        container != nil && dismissalTask == nil
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
    func beginUse(
        _ request: LoadingContentRequest,
        message: String?,
        placement: DialogPlacement?
    ) async throws -> LoadingUseToken {
        await waitForPendingDismissal()
        guard activeCount > 0 else {
            // 新しい世代。ここで初めてコンテンツを解決するので、失敗は開始そのものの失敗になる。
            let style = settings.style
            let resolved = try makeContent(for: request, style: style)
            generation += 1
            activeCount = 1
            displayedStyle = style
            latestMessage = message
            latestProgress = nil
            startDisplay(resolved, placement: placement)
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
    func setMessage(_ message: String?) {
        guard activeCount > 0, builtinContentView != nil else { return }
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

    /// 解決済みの中身から器を組み立てて取り付ける。
    ///
    /// 取り付け先が無いときは器を作らない。表示は成立しないが合流状態は成立し、
    /// 呼び出し元の処理は通常どおり実行される (提示環境の不在は構成ミスではない)。
    private func startDisplay(_ resolved: LoadingResolvedContent, placement: DialogPlacement?) {
        builtinContentView = resolved.builtinContentView
        customViewModel = resolved.viewModel
        refreshBuiltinText()
        guard let hostView = presentationSurface.hostView else { return }
        let container = LoadingContainerViewController(content: resolved.content, placement: placement)
        self.container = container
        container.attach(to: hostView)
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
