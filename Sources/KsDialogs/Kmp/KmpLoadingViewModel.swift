#if canImport(UIKit)
import Foundation

/// KMP 共有コードの ViewModel を、ライブラリ内部の Loading の ViewModel 契約に載せる包み。
///
/// 共有コードの ViewModel は iOS Native の ViewModel 契約に準拠しないため、状態の正へはこの包みで渡す。
/// 進捗の受け口は常に実装し、転送先が無いときは何もしない — 共有 VM が進捗を受け取るかどうかの判定は
/// 共有コード側が行い、その結果が [progress] として渡る (kmp/ADR-0002)。
final class KmpLoadingViewModel: LoadingViewModel, LoadingProgressReceiver, @unchecked Sendable {
    /// 包んだ共有コードの ViewModel。中身の生成はこれを factory へ渡して行う。
    let viewModel: Any

    private let progress: (@Sendable (Double) -> Void)?

    init(viewModel: Any, progress: (@Sendable (Double) -> Void)?) {
        self.viewModel = viewModel
        self.progress = progress
    }

    @MainActor
    func onProgress(_ progress: Double) {
        self.progress?(progress)
    }
}

extension LoadingContentRequest {
    /// 共有コードの ViewModel からカスタム Loading の表示要求を作る。
    ///
    /// 解決キーになるのは共有コードで定義した ViewModel のクラスで、中身の生成も共有 VM をそのまま
    /// factory へ渡す。状態の正へ渡るのは包みのほうなので、レジストリを読まないインライン形の要求に
    /// 解決済みの factory を載せて渡す (登録内容はこの経路でも変化しない。core/ADR-0013)。
    ///
    /// - Throws: 共有 VM の型に対する View factory が未登録なら `DialogError.viewFactoryNotRegistered`。
    @MainActor
    static func kmp(
        viewModel: Any,
        progress: (@Sendable (Double) -> Void)?,
        registry: LoadingViewRegistry
    ) throws -> LoadingContentRequest {
        let viewModelType = type(of: viewModel)
        guard let factory = registry.factory(forKey: DialogViewModelKey(viewModelType)) else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        let boxedViewModel = UncheckedSendableBox(viewModel)
        return .inline(
            viewModel: KmpLoadingViewModel(viewModel: viewModel, progress: progress),
            factory: LoadingViewFactory { _ in try factory.makeContent(boxedViewModel.value) }
        )
    }
}
#endif
