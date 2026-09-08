#if canImport(UIKit)
import SwiftUI
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// KMP 共有コードの ViewModel の代わりに使う、利用者が書くのと同じ形の型。
/// 共有コードの ViewModel は iOS Native の ViewModel 契約に準拠しないため、素のクラスで表す。
final class ConsumerSharedDialogViewModel {
    let message: String

    init(message: String) {
        self.message = message
    }
}

/// KMP 向け Swift 公開面のコンパイル検証。
///
/// 型付き登録 (結果型の有無 × 従来 View 系 / SwiftUI)・型付き show (結果型の有無)・
/// 添付 DSL について、**型注釈を足さずに書けること**を既定のビルドの中で確かめる。
/// 検証はコンパイルが通ること自体であり、実行時の挙動は別のテストが受け持つ。
@MainActor
enum KmpApiSurfaceCompileChecks {
    // MARK: 型付き登録 (従来 View 系)

    /// result を省略した登録の結果報告口は真偽値に型付く。
    static func registersUIViewContentWithDefaultResult(dialogs: Dialog) {
        dialogs.kmp.register(ConsumerSharedDialogViewModel.self) { _, notifier in
            let notifier: DialogNotifier<Bool> = notifier
            notifier.complete(true)
            return DialogTestContentView()
        }
    }

    /// result を指定した登録の結果報告口はその型に型付く。
    static func registersUIViewContentWithDeclaredResult(dialogs: Dialog) {
        dialogs.kmp.register(ConsumerSharedDialogViewModel.self, result: String.self) { _, notifier in
            let notifier: DialogNotifier<String> = notifier
            notifier.complete("入力")
            return DialogTestContentView()
        }
    }

    // MARK: 型付き登録 (SwiftUI)

    /// SwiftUI の View を返す factory でも登録できる。
    static func registersSwiftUIContentWithDefaultResult(dialogs: Dialog) {
        dialogs.kmp.register(ConsumerSharedDialogViewModel.self) { viewModel, notifier in
            VStack {
                Text(viewModel.message)
                Button("OK") { notifier.complete(true) }
            }
        }
    }

    /// SwiftUI の中身にカスタム結果型を組み合わせられる。
    static func registersSwiftUIContentWithDeclaredResult(dialogs: Dialog) {
        dialogs.kmp.register(ConsumerSharedDialogViewModel.self, result: String.self) { viewModel, notifier in
            Button(viewModel.message) { notifier.complete("入力") }
        }
    }

    /// 器の属性は SwiftUI の中身への添付で供給できる (iOS Native の直接登録と同じ書き方)。
    static func attachesAttributesToSwiftUIContent(dialogs: Dialog) {
        dialogs.kmp.register(ConsumerSharedDialogViewModel.self) { viewModel, notifier in
            Button(viewModel.message) { notifier.complete(true) }
                .ksDialogOptions(DialogOptions(layoutArea: .window, isCanceledOnTouchOutside: false))
                .ksDialogPlacement(DialogPlacement(verticalAlignment: .end))
        }
    }

    // MARK: 1引数 factory の登録と結果報告口の取り出し

    /// ViewModel だけを受け取る factory で登録でき、報告口は KMP 面のアクセサから引ける。
    static func registersUIViewContentWithoutNotifierArgument(dialogs: Dialog) {
        dialogs.kmp.register(ConsumerSharedDialogViewModel.self) { viewModel in
            let notifier: DialogNotifier<Bool>? = try? dialogs.kmp.notifier(for: viewModel)
            notifier?.complete(true)
            return DialogTestContentView()
        }
    }

    /// 結果型を指定した1引数 factory の報告口は、同じ型を指定して引ける。
    static func registersUIViewContentWithoutNotifierArgumentAndDeclaredResult(dialogs: Dialog) {
        dialogs.kmp.register(ConsumerSharedDialogViewModel.self, result: String.self) { viewModel in
            let notifier: DialogNotifier<String>? = try? dialogs.kmp.notifier(
                for: viewModel,
                result: String.self
            )
            notifier?.complete("入力")
            return DialogTestContentView()
        }
    }

    /// SwiftUI の中身も ViewModel だけを受け取る factory で登録できる。
    static func registersSwiftUIContentWithoutNotifierArgument(dialogs: Dialog) {
        dialogs.kmp.register(ConsumerSharedDialogViewModel.self, result: String.self) { viewModel in
            Button(viewModel.message) {
                try? dialogs.kmp.notifier(for: viewModel, result: String.self)?.complete("入力")
            }
        }
    }

    /// 報告口の取り出しは失敗しうるため、呼び出し側は失敗を捕まえられる。
    static func handlesAccessorFailure(dialogs: Dialog, viewModel: ConsumerSharedDialogViewModel) -> String? {
        do {
            return try dialogs.kmp.notifier(for: viewModel, result: String.self) == nil ? nil : "表示中"
        } catch let error as KsDialogsKmpError {
            return handlesEveryKmpError(error)
        } catch {
            return nil
        }
    }

    // MARK: 型付き show

    /// result を省略した show は真偽値の結果を返す。
    static func showsWithDefaultResult(dialogs: Dialog) async throws {
        let result: DialogResult<Bool> = try await dialogs.kmp.show(
            ConsumerSharedDialogViewModel(message: "")
        )
        _ = result
    }

    /// result を指定した show はその型の結果を返す。
    static func showsWithDeclaredResult(dialogs: Dialog) async throws {
        let result: DialogResult<String> = try await dialogs.kmp.show(
            ConsumerSharedDialogViewModel(message: ""),
            result: String.self
        )
        _ = result
    }

    /// show には placement を渡せる (意味は iOS Native の show と同じ)。
    static func showsWithPlacement(dialogs: Dialog) async throws {
        _ = try await dialogs.kmp.show(
            ConsumerSharedDialogViewModel(message: ""),
            placement: DialogPlacement(verticalAlignment: .end)
        )
        _ = try await dialogs.kmp.show(
            ConsumerSharedDialogViewModel(message: ""),
            result: String.self,
            placement: DialogPlacement(verticalAlignment: .end)
        )
    }

    /// 画面が保持している共有 VM をそのまま渡せる。
    static func showsViewModelHeldByScreen(dialogs: Dialog, screen: ConsumerSharedDialogScreen) async throws {
        _ = try await dialogs.kmp.show(screen.viewModel)
    }

    // MARK: 公開エラー型の形

    /// KMP 向け公開面に固有の失敗は2つだけで、利用者はこの2つを書けば網羅できる。
    /// 判別が増えれば、既定の枝を持たないこの `switch` がコンパイルできなくなる。
    static func handlesEveryKmpError(_ error: KsDialogsKmpError) -> String {
        switch error {
        case .notRegistered(let viewModelType):
            viewModelType
        case .resultTypeMismatch(let expected, let actual):
            "\(expected) / \(actual)"
        }
    }
}

/// 共有 VM を保持したまま show を呼ぶ、利用者が書くのと同じ形の画面。
@MainActor
final class ConsumerSharedDialogScreen {
    let viewModel = ConsumerSharedDialogViewModel(message: "")

    /// 既定エントリから型付き show を呼べる。
    func confirm() async throws -> DialogResult<Bool> {
        try await Dialog.shared.kmp.show(viewModel)
    }
}
#endif
