#if canImport(UIKit)
import SwiftUI
import UIKit

/// カスタム Toast の中身の生成関数の型消去表現。
///
/// 中身の内部表現 (`DialogContent`) と載せ方は Dialog / Loading と共有する (core/ADR-0029)。
/// ViewModel の型が factory の想定と一致しない場合は nil を返す。
/// factory 自身が投げた失敗はそのまま伝え、受理後の失敗としてその表示だけの破棄に使う。
struct ToastViewFactory: Sendable {
    let makeContent: @MainActor @Sendable (_ viewModel: Any) throws -> DialogContent?
}

extension ToastViewFactory {
    /// 従来 View 系の factory を型消去する。
    static func make<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) -> ToastViewFactory {
        ToastViewFactory { viewModel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return try DialogContent(view: factory(typedViewModel))
        }
    }

    /// SwiftUI の factory を型消去する。ホスティングは Dialog と同じ変換を通る (core/ADR-0011)。
    static func make<ViewModel: ToastViewModel, Content: View>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) -> ToastViewFactory {
        ToastViewFactory { viewModel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return try DialogSwiftUIHost.makeContent(factory(typedViewModel))
        }
    }
}
#endif
