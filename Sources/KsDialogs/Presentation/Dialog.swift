#if canImport(UIKit)
import SwiftUI
import UIKit

/// ダイアログ表示の既定エントリ。
/// `Dialog.shared` で手軽に呼び出せるほか、`Dialog()` を `KsDialog` として DI 注入しても
/// 同じレジストリ (`DialogViewRegistry.shared`) を共有する (core/ADR-0002・0004)。
public final class Dialog: KsDialog {
    /// 既定の singleton エントリ。
    public static let shared = Dialog()

    public let registry: DialogViewRegistry

    /// KMP 共有コードの ViewModel を扱う型付きの入口。このエントリと同じレジストリを共有する。
    /// iOS Native だけで完結するアプリは使わない (kmp/ADR-0003)。
    public let kmp: KsDialogsKmp

    private let presentationSurface: any DialogPresentationSurface

    /// 既定のレジストリと提示先解決を使うインスタンスを作る。
    public convenience init() {
        self.init(presentationSurface: UIKitDialogPresentationSurface())
    }

    init(registry: DialogViewRegistry = .shared, presentationSurface: any DialogPresentationSurface) {
        self.registry = registry
        self.presentationSurface = presentationSurface
        kmp = KsDialogsKmp(registry: registry, presentationSurface: presentationSurface)
    }

    public func show<ViewModel: DialogViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil
    ) async throws -> DialogResult<ViewModel.Result> {
        let outcome = try await DialogPresenter.present(
            viewModel: viewModel,
            registry: registry,
            presentationSurface: presentationSurface,
            placement: placement
        )
        return try Self.restoreResult(outcome, for: ViewModel.self)
    }

    public func show<ViewModel: DialogViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> UIView
    ) async throws -> DialogResult<ViewModel.Result> {
        try await showInline(
            viewModel,
            placement: placement,
            factory: DialogViewFactory.make(ViewModel.self, factory: factory)
        )
    }

    public func show<ViewModel: DialogViewModel, Content: View>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> Content
    ) async throws -> DialogResult<ViewModel.Result> {
        try await showInline(
            viewModel,
            placement: placement,
            factory: DialogViewFactory.make(ViewModel.self, factory: factory)
        )
    }

    public func show<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement? = nil,
        configure: (@MainActor @Sendable (ViewModel) async throws -> Void)? = nil
    ) async throws -> DialogResult<ViewModel.Result> {
        // 解決は呼び出し時点のエントリのスナップショットで行い、以後の再登録には影響されない。
        let key = DialogViewModelKey(viewModelType)
        let entry = registry.entry(forKey: key)
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
        let outcome = try await DialogPresenter.present(
            viewModel: viewModel,
            factory: viewFactory,
            presentationSurface: presentationSurface,
            placement: placement
        )
        return try Self.restoreResult(outcome, for: ViewModel.self)
    }

    /// ViewModel を生成し、configure の完了まで待つ。どちらも UI スレッド (MainActor) で実行する。
    /// ここで失敗した場合は提示に進まないため、結果報告口の紐付けもまだ作られていない。
    @MainActor
    private static func makeViewModel<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        using viewModelFactory: DialogViewModelFactory,
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

    /// 型消去した factory をそのまま提示層へ渡す。レジストリは経由しない (core/ADR-0013)。
    private func showInline<ViewModel: DialogViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        factory: DialogViewFactory
    ) async throws -> DialogResult<ViewModel.Result> {
        let outcome = try await DialogPresenter.present(
            viewModel: viewModel,
            factory: factory,
            presentationSurface: presentationSurface,
            placement: placement
        )
        return try Self.restoreResult(outcome, for: ViewModel.self)
    }

    /// 型消去された結果を ViewModel の宣言結果型へ復元する。
    private static func restoreResult<ViewModel: DialogViewModel>(
        _ outcome: DialogOutcome,
        for viewModelType: ViewModel.Type
    ) throws -> DialogResult<ViewModel.Result> {
        switch outcome {
        case .cancelled:
            return .cancelled
        case .completed(let value):
            guard let typedValue = value as? ViewModel.Result else {
                throw DialogError.resultTypeMismatch(
                    expected: String(describing: ViewModel.Result.self),
                    actual: String(describing: type(of: value))
                )
            }
            return .completed(typedValue)
        }
    }
}
#endif
