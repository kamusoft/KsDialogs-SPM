#if canImport(UIKit)

/// Toast のレジストリが保持する ViewModel の生成関数の型消去表現 (core/ADR-0035)。
/// 型指定 show はこれで ViewModel を作ってから configure・View 生成へ進む。
struct ToastViewModelFactory: Sendable {
    let makeViewModel: @MainActor @Sendable () -> Any
}

extension ToastViewModelFactory {
    /// 型付きの ViewModel factory を型消去する。
    static func make<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable () -> ViewModel
    ) -> ToastViewModelFactory {
        ToastViewModelFactory { factory() }
    }
}
#endif
