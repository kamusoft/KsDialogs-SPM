#if canImport(UIKit)
import SwiftUI
import UIKit

/// カスタム Loading の中身の生成関数の型消去表現。
///
/// 結果報告口を持たないこと以外は `DialogViewFactory` と同じ役割で、
/// 中身の内部表現 (`DialogContent`) と載せ方は Dialog と共有する (core/ADR-0022)。
/// ViewModel の型が factory の想定と一致しない場合は nil を返す。
/// factory 自身が投げた失敗はそのまま伝え、開始そのものの失敗に使う。
struct LoadingViewFactory: Sendable {
    let makeContent: @MainActor @Sendable (_ viewModel: Any) throws -> DialogContent?
}

extension LoadingViewFactory {
    /// 従来 View 系の factory を型消去する。
    static func make<ViewModel: LoadingViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) -> LoadingViewFactory {
        LoadingViewFactory { viewModel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return try DialogContent(view: factory(typedViewModel))
        }
    }

    /// SwiftUI の factory を型消去する。ホスティングは Dialog と同じ変換を通る (core/ADR-0011)。
    static func make<ViewModel: LoadingViewModel, Content: View>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) -> LoadingViewFactory {
        LoadingViewFactory { viewModel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return try DialogSwiftUIHost.makeContent(factory(typedViewModel))
        }
    }
}
#endif
