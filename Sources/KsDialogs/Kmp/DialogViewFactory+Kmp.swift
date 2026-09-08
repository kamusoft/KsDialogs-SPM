#if canImport(UIKit)
import SwiftUI
import UIKit

extension DialogViewFactory {
    /// 共有コードの ViewModel 向けの、従来 View 系 factory を型消去する。
    ///
    /// 共有 VM は iOS Native の ViewModel 契約に準拠しないため、結果型は登録時の型引数から受け取り、
    /// 結果報告口をその型に固定する。出来上がる内部表現は Native の登録経路と同じ1本で、
    /// 提示・結果・レイアウトの経路は共有される (core/ADR-0011)。
    static func make<ViewModel: AnyObject, Result: Sendable>(
        _ viewModelClass: ViewModel.Type,
        result: Result.Type,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<Result>) -> UIView
    ) -> DialogViewFactory {
        DialogViewFactory(declaredResultType: DialogDeclaredResultType(result)) { viewModel, resultChannel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return DialogContent(
                view: factory(typedViewModel, DialogNotifier(resultChannel: resultChannel))
            )
        }
    }

    /// 共有コードの ViewModel 向けの、SwiftUI factory を型消去する。
    /// ホスティングはこの変換の中で完結し、従来 View 系と同じ内部表現になる。
    static func make<ViewModel: AnyObject, Result: Sendable, Content: View>(
        _ viewModelClass: ViewModel.Type,
        result: Result.Type,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<Result>) -> Content
    ) -> DialogViewFactory {
        DialogViewFactory(declaredResultType: DialogDeclaredResultType(result)) { viewModel, resultChannel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            let content = factory(typedViewModel, DialogNotifier(resultChannel: resultChannel))
            return DialogSwiftUIHost.makeContent(content)
        }
    }

    /// 共有コードの ViewModel 向けの、ViewModel だけを受け取る従来 View 系 factory を型消去する
    /// (core/ADR-0018)。
    ///
    /// 結果報告口は中身の中から KMP 面のアクセサ (`notifier(for:result:)`) で取り出す。
    /// 紐付けは提示層が factory を呼ぶ前に済ませているため、factory 本体からも引ける。
    static func make<ViewModel: AnyObject, Result: Sendable>(
        _ viewModelClass: ViewModel.Type,
        result: Result.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> UIView
    ) -> DialogViewFactory {
        DialogViewFactory(declaredResultType: DialogDeclaredResultType(result)) { viewModel, _ in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return DialogContent(view: factory(typedViewModel))
        }
    }

    /// 共有コードの ViewModel 向けの、ViewModel だけを受け取る SwiftUI factory を型消去する
    /// (core/ADR-0018)。
    static func make<ViewModel: AnyObject, Result: Sendable, Content: View>(
        _ viewModelClass: ViewModel.Type,
        result: Result.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> Content
    ) -> DialogViewFactory {
        DialogViewFactory(declaredResultType: DialogDeclaredResultType(result)) { viewModel, _ in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return DialogSwiftUIHost.makeContent(factory(typedViewModel))
        }
    }
}
#endif
