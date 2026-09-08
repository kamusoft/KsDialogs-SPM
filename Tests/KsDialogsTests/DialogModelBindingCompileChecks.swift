#if canImport(UIKit)
import SwiftUI
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// ViewModel 主導の呼び出し面で利用者が書く形の ViewModel。
/// 状態は表示の直前に configure から設定されるため MainActor に閉じる。
@MainActor
final class ConsumerModelBindingViewModel: DialogViewModel {
    var message: String = ""

    nonisolated init() {}

    /// 中身を経由せず ViewModel 自身が結果を報告する形。
    func confirm() {
        notifier?.complete(true)
    }
}

/// ViewModel 主導の呼び出し面 (VM 引数のみの登録・ViewModel factory 登録・`vm.notifier`・型指定 show) の
/// コンパイル検証。
///
/// 正の検証 (これらが型注釈を足さずに書けること) は既定のビルドに含まれる。
/// 負の検証は禁止形状ごとに別のフラグへ分けてあり、**フラグを1つだけ定義したビルドが失敗すること**が
/// 期待結果になる:
///
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_VALUE_TYPE_VIEW_MODEL'
@MainActor
enum DialogModelBindingCompileChecks {
    // MARK: VM 引数のみの登録

    /// 従来 View 系の中身を ViewModel 引数だけの factory で登録でき、`vm.notifier` が宣言結果型に型付く。
    static func MB_IO_01_registersViewModelOnlyUIKitFactory(registry: DialogViewRegistry) {
        registry.register(ConsumerModelBindingViewModel.self) { viewModel in
            let notifier: DialogNotifier<Bool>? = viewModel.notifier
            notifier?.complete(true)
            return DialogTestContentView()
        }
    }

    /// SwiftUI の中身を ViewModel 引数だけの factory で登録できる。
    static func MB_IO_01_registersViewModelOnlySwiftUIFactory(registry: DialogViewRegistry) {
        registry.register(ConsumerModelBindingViewModel.self) { viewModel in
            Button(viewModel.message) {
                viewModel.notifier?.complete(true)
            }
        }
    }

    // MARK: ViewModel factory の登録

    /// ViewModel factory を登録できる。View factory の登録とはスロットが別で共存する。
    static func MB_IO_01_registersViewModelFactory(registry: DialogViewRegistry) {
        registry.register(ConsumerModelBindingViewModel.self) {
            ConsumerModelBindingViewModel()
        }
    }

    // MARK: 型指定 show

    /// configure なしの型指定 show は宣言結果型の結果を返す。
    static func MB_IO_01_typedShowWithoutConfigure(dialogs: any KsDialog) async throws {
        let result: DialogResult<Bool> = try await dialogs.show(ConsumerModelBindingViewModel.self)
        _ = result
    }

    /// configure つきの型指定 show を書ける。
    static func MB_IO_01_typedShowWithConfigure(dialogs: any KsDialog) async throws {
        let result: DialogResult<Bool> = try await dialogs.show(
            ConsumerModelBindingViewModel.self
        ) { viewModel in
            viewModel.message = "確認"
        }
        _ = result
    }

    /// configure は非同期でも書ける。
    static func MB_IO_01_typedShowWithAsynchronousConfigure(dialogs: any KsDialog) async throws {
        _ = try await dialogs.show(ConsumerModelBindingViewModel.self) { viewModel in
            try await Task.sleep(for: .milliseconds(1))
            viewModel.message = "非同期で用意"
        }
    }

    /// 型指定 show でも配置を渡せる。
    static func MB_IO_01_typedShowWithPlacement(dialogs: any KsDialog) async throws {
        _ = try await dialogs.show(ConsumerModelBindingViewModel.self, placement: DialogPlacement())
    }
}

#if KSDIALOGS_NEGATIVE_CHECK_VALUE_TYPE_VIEW_MODEL
/// 値型は ViewModel 契約に準拠できない (core/ADR-0018)。
struct ConsumerValueDialogViewModel: DialogViewModel {
    typealias Result = Bool
}

enum DialogValueTypeViewModelNegativeCheck {
    /// 期待する診断: non-class type 'ConsumerValueDialogViewModel' cannot conform to
    /// class protocol 'DialogViewModel'
    static func MB_IO_02_rejectsValueTypeViewModel() {
        _ = ConsumerValueDialogViewModel()
    }
}
#endif
#endif
