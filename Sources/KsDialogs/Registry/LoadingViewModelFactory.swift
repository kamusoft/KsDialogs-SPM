#if canImport(UIKit)

/// Loading のレジストリが保持する ViewModel の生成関数の型消去表現 (core/ADR-0035)。
/// 型指定 show / start はこれで ViewModel を作ってから configure・View 生成へ進む。
struct LoadingViewModelFactory: Sendable {
    let makeViewModel: @MainActor @Sendable () -> Any
}

extension LoadingViewModelFactory {
    /// 型付きの ViewModel factory を型消去する。
    static func make<ViewModel: LoadingViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable () -> ViewModel
    ) -> LoadingViewModelFactory {
        LoadingViewModelFactory { factory() }
    }
}
#endif
