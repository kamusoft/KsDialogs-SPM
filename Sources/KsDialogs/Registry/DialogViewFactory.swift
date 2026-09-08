#if canImport(UIKit)
import SwiftUI
import UIKit

/// レジストリと提示層が保持する中身の生成関数の型消去表現。
/// ViewModel と結果チャネルを受け取り、そのダイアログの中身を新規に生成する。
/// ViewModel の型が factory の想定と一致しない場合は nil を返す。
/// factory 自身が投げた失敗はそのまま伝え、提示そのものの失敗に使う。
struct DialogViewFactory: Sendable {
    let makeContent: @MainActor @Sendable (
        _ viewModel: Any,
        _ resultChannel: DialogResultChannel
    ) throws -> DialogContent?

    /// 登録のときに固定された結果値の型。ViewModel 自身が結果型を宣言する経路では持たない。
    let declaredResultType: DialogDeclaredResultType?

    init(
        declaredResultType: DialogDeclaredResultType? = nil,
        makeContent: @escaping @MainActor @Sendable (
            _ viewModel: Any,
            _ resultChannel: DialogResultChannel
        ) throws -> DialogContent?
    ) {
        self.declaredResultType = declaredResultType
        self.makeContent = makeContent
    }
}

extension DialogViewFactory {
    /// 従来 View 系の factory を型消去する。
    ///
    /// 登録経路とインライン show 経路はこの1つの変換を共有するため、
    /// どちらから渡した factory も同じ内部表現になる (core/ADR-0011・0013)。
    static func make<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> UIView
    ) -> DialogViewFactory {
        DialogViewFactory { viewModel, resultChannel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return try DialogContent(view: factory(typedViewModel, DialogNotifier(resultChannel: resultChannel)))
        }
    }

    /// SwiftUI の factory を型消去する。ホスティングはこの変換の中で完結する。
    static func make<ViewModel: DialogViewModel, Content: View>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> Content
    ) -> DialogViewFactory {
        DialogViewFactory { viewModel, resultChannel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            let content = try factory(typedViewModel, DialogNotifier(resultChannel: resultChannel))
            return DialogSwiftUIHost.makeContent(content)
        }
    }

    /// ViewModel だけを受け取る従来 View 系の factory を型消去する (core/ADR-0018)。
    ///
    /// 結果報告口は中身の中から `viewModel.notifier` で取り出す。
    /// 紐付けは提示層が factory を呼ぶ前に済ませているため、factory 本体からも読める。
    static func make<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) -> DialogViewFactory {
        DialogViewFactory { viewModel, _ in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return try DialogContent(view: factory(typedViewModel))
        }
    }

    /// ViewModel だけを受け取る SwiftUI の factory を型消去する (core/ADR-0018)。
    static func make<ViewModel: DialogViewModel, Content: View>(
        _ viewModelType: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) -> DialogViewFactory {
        DialogViewFactory { viewModel, _ in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return try DialogSwiftUIHost.makeContent(factory(typedViewModel))
        }
    }
}
#endif
