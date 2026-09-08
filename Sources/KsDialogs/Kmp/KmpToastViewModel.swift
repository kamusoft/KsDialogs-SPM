#if canImport(UIKit)
import Foundation

/// KMP 共有コードの ViewModel を、ライブラリ内部の Toast の ViewModel 契約に載せる包み。
///
/// 共有コードの ViewModel は iOS Native の ViewModel 契約に準拠しないため、状態の正へはこの包みで渡す。
/// 包みが運ぶのは中身の生成に使う共有 VM そのものだけで、Toast には進捗も結果も無い (kmp/ADR-0002)。
final class KmpToastViewModel: ToastViewModel, @unchecked Sendable {
    /// 包んだ共有コードの ViewModel。中身の生成はこれを factory へ渡して行う。
    let viewModel: Any

    init(viewModel: Any) {
        self.viewModel = viewModel
    }
}

extension ToastContentRequest {
    /// 共有コードの ViewModel からカスタム Toast の表示要求を作る。
    ///
    /// 解決キーになるのは共有コードで定義した ViewModel のクラスで、中身の生成も共有 VM をそのまま
    /// factory へ渡す。状態の正へ渡るのは包みのほうなので、レジストリを読まないインライン形の要求に
    /// 解決済みの factory を載せて渡す (登録内容はこの経路でも変化しない。core/ADR-0013)。
    ///
    /// 未登録の型はここで弾くため、共有コードから見た解決の失敗は show の呼び出し時点で同期に届く。
    ///
    /// - Throws: 共有 VM の型に対する View factory が未登録なら `DialogError.viewFactoryNotRegistered`。
    static func kmp(viewModel: Any, registry: ToastViewRegistry) throws -> ToastContentRequest {
        let viewModelType = type(of: viewModel)
        guard let factory = registry.factory(forKey: DialogViewModelKey(viewModelType)) else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        let boxedViewModel = UncheckedSendableBox(viewModel)
        return .inline(
            viewModel: KmpToastViewModel(viewModel: viewModel),
            factory: ToastViewFactory { _ in try factory.makeContent(boxedViewModel.value) }
        )
    }
}
#endif
