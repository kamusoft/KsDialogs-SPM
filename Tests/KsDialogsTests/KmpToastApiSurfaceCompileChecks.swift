#if canImport(UIKit)
import SwiftUI
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// KMP 共有コードの ViewModel の代わりに使う、利用者が書くのと同じ形の型。
/// 共有コードの ViewModel は iOS Native の Toast の契約に準拠しないため、素のクラスで表す。
final class ConsumerSharedToastViewModel {
    let message: String

    init(message: String) {
        self.message = message
    }
}

/// KMP 向け Swift 公開面 (Toast) のコンパイル検証。
///
/// 型付き登録 (従来 View 系 / SwiftUI) と共有 VM の表示について、
/// **内部の互換面の型を書かずに書けること**を既定のビルドの中で確かめる。
/// 検証はコンパイルが通ること自体であり、実行時の挙動は別のテストが受け持つ。
@MainActor
enum KmpToastApiSurfaceCompileChecks {
    // MARK: 型付き登録

    /// 従来 View 系の中身を共有 VM の型に紐付けて登録できる。
    static func registersUIViewContent(toast: Toast) {
        toast.kmp.register(ConsumerSharedToastViewModel.self) { _ in
            DialogTestContentView()
        }
    }

    /// SwiftUI の中身も同名の登録で書ける。
    static func registersSwiftUIContent(toast: Toast) {
        toast.kmp.register(ConsumerSharedToastViewModel.self) { viewModel in
            Text(viewModel.message)
        }
    }

    /// 器の属性は SwiftUI の中身への添付で供給できる (iOS Native の直接登録と同じ書き方)。
    static func attachesAttributesToSwiftUIContent(toast: Toast) {
        toast.kmp.register(ConsumerSharedToastViewModel.self) { viewModel in
            Text(viewModel.message)
                .ksDialogPlacement(DialogPlacement(verticalAlignment: .end))
                .ksDialogTransition(DialogTransition.fade())
        }
    }

    // MARK: 表示

    /// 共有 VM をそのまま渡して表示できる。duration も配置も既定に委ねられる。
    static func showsSharedViewModel(toast: Toast) throws {
        try toast.kmp.show(ConsumerSharedToastViewModel(message: "保存しました"))
    }

    /// 表示には duration と placement を渡せる (意味は iOS Native の表示と同じ)。
    static func showsSharedViewModelWithDurationAndPlacement(toast: Toast) throws {
        try toast.kmp.show(
            ConsumerSharedToastViewModel(message: "保存しました"),
            duration: 3000,
            placement: DialogPlacement(verticalAlignment: .end)
        )
    }

    /// 既定エントリからも同じ書き方で登録と表示ができる。
    static func usesDefaultEntryPoint() throws {
        Toast.shared.kmp.register(ConsumerSharedToastViewModel.self) { _ in
            DialogTestContentView()
        }
        try Toast.shared.kmp.show(ConsumerSharedToastViewModel(message: "保存しました"))
    }
}
#endif
