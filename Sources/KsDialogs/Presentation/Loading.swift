#if canImport(UIKit)
import SwiftUI
import UIKit

/// ローディング表示の既定エントリ。
/// `Loading.shared` で手軽に呼び出せるほか、`Loading()` を `KsLoading` として DI 注入しても
/// 同じ状態 (合流カウント・表示世代・表示中のコンテンツ) を共有する (core/ADR-0002・0024)。
///
/// この型は状態を持たず、すべての呼び出しをプロセス内で唯一の coordinator へ委譲する。
/// そのため既定シングルトンと注入したインスタンスを混ぜて使っても表示は1つに合流する。
public final class Loading: KsLoading {
    /// 既定の singleton エントリ。
    public static let shared = Loading()

    /// 状態の正。既定の入口はすべて同じ実体を指す。
    let coordinator: LoadingCoordinator

    /// KMP 共有コードの ViewModel を扱うカスタム Loading の入口。
    /// 共有コードを持たず iOS Native だけで完結するアプリは使わない (kmp/ADR-0003)。
    public let kmp: KsLoadingKmp

    /// 既定の状態・レジストリ・取り付け先解決を使うインスタンスを作る。
    public convenience init() {
        self.init(coordinator: .shared)
    }

    init(coordinator: LoadingCoordinator) {
        self.coordinator = coordinator
        kmp = KsLoadingKmp(coordinator: coordinator)
    }

    public var registry: LoadingViewRegistry {
        coordinator.registry
    }

    public var style: LoadingStyle {
        get { coordinator.settings.style }
        set { coordinator.settings.style = newValue }
    }

    public var options: DialogOptions {
        get { coordinator.settings.options }
        set { coordinator.settings.options = newValue }
    }

    public func show(message: String? = nil, placement: DialogPlacement? = nil) async {
        // 既定ローディングにはコンテンツ解決の失敗が無いため、この経路は失敗しない。
        _ = try? await coordinator.beginUse(.builtin, message: message, placement: placement)
    }

    public func show<ViewModel: LoadingViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil
    ) async throws {
        _ = try await coordinator.beginUse(
            .registered(viewModel: viewModel),
            message: nil,
            placement: placement
        )
    }

    public func show<ViewModel: LoadingViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) async throws {
        _ = try await beginInlineUse(
            viewModel,
            placement: placement,
            factory: LoadingViewFactory.make(ViewModel.self, factory: factory)
        )
    }

    public func show<ViewModel: LoadingViewModel, Content: View>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) async throws {
        _ = try await beginInlineUse(
            viewModel,
            placement: placement,
            factory: LoadingViewFactory.make(ViewModel.self, factory: factory)
        )
    }

    public func show<ViewModel: LoadingViewModel>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement? = nil,
        configure: (@MainActor @Sendable (ViewModel) async throws -> Void)? = nil
    ) async throws {
        _ = try await beginTypedUse(viewModelType, placement: placement, configure: configure)
    }

    public func hide() async {
        await coordinator.hide()
    }

    public func setMessage(_ message: String?) async {
        await coordinator.setMessage(message)
    }

    public func start<T: Sendable>(
        message: String? = nil,
        placement: DialogPlacement? = nil,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        let token = try await coordinator.beginUse(.builtin, message: message, placement: placement)
        return try await runScope(token: token, action)
    }

    public func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        let token = try await coordinator.beginUse(
            .registered(viewModel: viewModel),
            message: nil,
            placement: placement
        )
        return try await runScope(token: token, action)
    }

    public func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        let token = try await beginInlineUse(
            viewModel,
            placement: placement,
            factory: LoadingViewFactory.make(ViewModel.self, factory: factory)
        )
        return try await runScope(token: token, action)
    }

    public func start<ViewModel: LoadingViewModel, Content: View, T: Sendable>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        let token = try await beginInlineUse(
            viewModel,
            placement: placement,
            factory: LoadingViewFactory.make(ViewModel.self, factory: factory)
        )
        return try await runScope(token: token, action)
    }

    public func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement? = nil,
        configure: (@MainActor @Sendable (ViewModel) async throws -> Void)? = nil,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        let token = try await beginTypedUse(viewModelType, placement: placement, configure: configure)
        return try await runScope(token: token, action)
    }

    /// 型指定の表示を開始する。
    ///
    /// 解決は呼び出し時点のエントリのスナップショットで行い、以後の再登録には影響されない。
    /// ViewModel の生成と configure を先に済ませてから状態の正へ渡すので、そこから先は
    /// インスタンスを渡す表示とまったく同じ合流判定に入る。
    private func beginTypedUse<ViewModel: LoadingViewModel>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement?,
        configure: (@MainActor @Sendable (ViewModel) async throws -> Void)?
    ) async throws -> LoadingUseToken {
        let entry = registry.entry(forKey: DialogViewModelKey(viewModelType))
        guard let viewModelFactory = entry?.viewModelFactory else {
            throw DialogError.viewModelFactoryNotRegistered(
                viewModelType: String(describing: viewModelType)
            )
        }
        guard let viewFactory = entry?.viewFactory else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        let viewModel = try await Self.makeViewModel(
            viewModelType,
            using: viewModelFactory,
            configure: configure
        )
        return try await coordinator.beginUse(
            .resolved(viewModel: viewModel, factory: viewFactory),
            message: nil,
            placement: placement
        )
    }

    /// ViewModel を生成し、configure の完了まで待つ。どちらも UI スレッド (MainActor) で実行する。
    /// ここで失敗した場合は表示に進まないため、合流1件も始まっていない。
    @MainActor
    private static func makeViewModel<ViewModel: LoadingViewModel>(
        _ viewModelType: ViewModel.Type,
        using viewModelFactory: LoadingViewModelFactory,
        configure: (@MainActor @Sendable (ViewModel) async throws -> Void)?
    ) async throws -> ViewModel {
        guard let viewModel = viewModelFactory.makeViewModel() as? ViewModel else {
            throw DialogError.viewModelFactoryTypeMismatch(
                viewModelType: String(describing: viewModelType)
            )
        }
        try await configure?(viewModel)
        return viewModel
    }

    /// 型消去した factory をそのまま状態の正へ渡す。レジストリは経由しない (core/ADR-0013)。
    private func beginInlineUse<ViewModel: LoadingViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        factory: LoadingViewFactory
    ) async throws -> LoadingUseToken {
        try await coordinator.beginUse(
            .inline(viewModel: viewModel, factory: factory),
            message: nil,
            placement: placement
        )
    }

    /// 合流1件を握ったまま処理を走らせ、成否によらず終了を1回だけ数える。
    ///
    /// 失敗を握り潰さずに伝播させつつ終了を数えるので、例外・キャンセルで表示が閉じ残らない。
    private func runScope<T: Sendable>(
        token: LoadingUseToken,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        let coordinator = coordinator
        let queue = LoadingReportQueue()
        // 報告口は任意スレッドから呼べる。受理は UI スレッド上で呼ばれた順に直列化される。
        let report: @Sendable (Double) -> Void = { progress in
            queue.enqueue { coordinator.report(progress: progress, token: token) }
        }
        do {
            let value = try await action(report)
            // 発行済みの報告を受理しきってから終了する。
            // そうしないと最終報告が終了処理に追い越され、旧世代の報告として捨てられる。
            await queue.drain()
            await coordinator.endUse(token)
            return value
        } catch {
            await queue.drain()
            await coordinator.endUse(token)
            throw error
        }
    }
}
#endif
