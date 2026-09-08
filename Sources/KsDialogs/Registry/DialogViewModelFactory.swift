#if canImport(UIKit)

/// レジストリが保持する ViewModel の生成関数の型消去表現 (core/ADR-0021)。
/// 型指定 show はこれで ViewModel を作ってから configure・View 生成へ進む。
struct DialogViewModelFactory: Sendable {
    let makeViewModel: @MainActor @Sendable () -> Any
}

extension DialogViewModelFactory {
    /// 型付きの ViewModel factory を型消去する。
    static func make<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable () -> ViewModel
    ) -> DialogViewModelFactory {
        DialogViewModelFactory { factory() }
    }
}
#endif
