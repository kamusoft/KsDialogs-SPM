#if canImport(UIKit)
import SwiftUI
import UIKit

/// Toast 表示の既定エントリ。
/// `Toast.shared` で手軽に呼び出せるほか、`Toast()` を `KsToast` として DI 注入しても
/// 同じ状態 (レジストリ・一括設定・表示中のリスト) を共有する (core/ADR-0002)。
///
/// この型は状態を持たず、すべての呼び出しをプロセス内で唯一の coordinator へ委譲する。
public final class Toast: KsToast {
    /// 既定の singleton エントリ。
    public static let shared = Toast()

    /// 状態の正。既定の入口はすべて同じ実体を指す。
    let coordinator: ToastCoordinator

    /// KMP 共有コードの ViewModel を扱うカスタム Toast の入口。
    /// 共有コードを持たず iOS Native だけで完結するアプリは使わない (kmp/ADR-0003)。
    public let kmp: KsToastKmp

    /// 既定の状態・レジストリ・取り付け先解決を使うインスタンスを作る。
    public convenience init() {
        self.init(coordinator: .shared)
    }

    init(coordinator: ToastCoordinator) {
        self.coordinator = coordinator
        kmp = KsToastKmp(coordinator: coordinator)
    }

    public var registry: ToastViewRegistry {
        coordinator.registry
    }

    public var style: ToastStyle {
        get { coordinator.settings.style }
        set { coordinator.settings.style = newValue }
    }

    public func show(message: String, duration: Int? = nil, placement: DialogPlacement? = nil) {
        // デフォルト View には中身の解決の失敗が無いため、この経路は失敗しない。
        try? coordinator.accept(.builtin(message: message), duration: duration, placement: placement)
    }

    public func show<ViewModel: ToastViewModel>(
        _ viewModel: ViewModel,
        duration: Int? = nil,
        placement: DialogPlacement? = nil
    ) throws {
        try coordinator.accept(
            .registered(viewModel: viewModel),
            duration: duration,
            placement: placement
        )
    }

    public func show<ViewModel: ToastViewModel>(
        _ viewModel: ViewModel,
        duration: Int? = nil,
        placement: DialogPlacement? = nil,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) throws {
        try acceptInline(
            viewModel,
            duration: duration,
            placement: placement,
            factory: ToastViewFactory.make(ViewModel.self, factory: factory)
        )
    }

    public func show<ViewModel: ToastViewModel, Content: View>(
        _ viewModel: ViewModel,
        duration: Int? = nil,
        placement: DialogPlacement? = nil,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) throws {
        try acceptInline(
            viewModel,
            duration: duration,
            placement: placement,
            factory: ToastViewFactory.make(ViewModel.self, factory: factory)
        )
    }

    public func show<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        duration: Int? = nil,
        placement: DialogPlacement? = nil,
        configure: (@MainActor @Sendable (ViewModel) throws -> Void)? = nil
    ) throws {
        // 解決は呼び出し時点のエントリのスナップショットで行い、以後の再登録には影響されない。
        // 未登録は受理そのものの失敗として、この場で同期に返す。
        let entry = registry.entry(forKey: DialogViewModelKey(viewModelType))
        guard let viewModelFactory = entry?.viewModelFactory else {
            throw DialogError.viewModelFactoryNotRegistered(
                viewModelType: String(describing: viewModelType)
            )
        }
        guard let viewFactory = entry?.viewFactory else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        try coordinator.accept(
            .typed(
                prepare: {
                    guard let viewModel = viewModelFactory.makeViewModel() as? ViewModel else {
                        throw DialogError.viewModelFactoryTypeMismatch(
                            viewModelType: String(describing: viewModelType)
                        )
                    }
                    try configure?(viewModel)
                    return viewModel
                },
                factory: viewFactory
            ),
            duration: duration,
            placement: placement
        )
    }

    /// 型消去した factory をそのまま状態の正へ渡す。レジストリは経由しない (core/ADR-0013)。
    private func acceptInline<ViewModel: ToastViewModel>(
        _ viewModel: ViewModel,
        duration: Int?,
        placement: DialogPlacement?,
        factory: ToastViewFactory
    ) throws {
        try coordinator.accept(
            .inline(viewModel: viewModel, factory: factory),
            duration: duration,
            placement: placement
        )
    }
}
#endif
