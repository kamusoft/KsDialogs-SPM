#if canImport(UIKit)

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// 結果型が ViewModel の宣言から導出されることのコンパイル検証。
///
/// 正の検証 (宣言結果型で受け取れること) は既定のビルドに含まれる。
/// 負の検証は禁止形状ごとに別のフラグへ分けてあり、**フラグを1つだけ定義したビルドが失敗すること**が
/// 期待結果になる:
///
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_RESULT_TYPE'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_NOTIFIER_VALUE'
enum DialogTypedResultCompileChecks {
    /// ViewModel が宣言した結果型でそのまま受け取れる。
    @MainActor
    static func acceptsDeclaredResultType(dialogs: any KsDialog) async throws {
        let result: DialogResult<Bool> = try await dialogs.show(ConsumerDialogViewModel(message: ""))
        _ = result
    }

    /// 結果報告口も宣言結果型に固定される。
    @MainActor
    static func notifierIsBoundToDeclaredResultType(registry: DialogViewRegistry) {
        registry.register(ConsumerDialogViewModel.self) { _, notifier in
            let notifier: DialogNotifier<Bool> = notifier
            notifier.complete(true)
            return DialogTestContentView()
        }
    }

    #if KSDIALOGS_NEGATIVE_CHECK_RESULT_TYPE
    /// 宣言結果型と異なる型では受け取れない。
    /// 期待する診断: cannot assign value of type 'DialogResult<ConsumerDialogViewModel.Result>'
    /// (aka 'DialogResult<Bool>') to type 'DialogResult<String>'
    @MainActor
    static func rejectsMismatchedResultType(dialogs: any KsDialog) async throws {
        let result: DialogResult<String> = try await dialogs.show(ConsumerDialogViewModel(message: ""))
        _ = result
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_NOTIFIER_VALUE
    /// 宣言結果型と異なる値では完了報告できない。
    /// 期待する診断: cannot convert value of type 'String' to expected argument type
    /// 'ConsumerDialogViewModel.Result' (aka 'Bool')
    @MainActor
    static func rejectsMismatchedNotifierValue(registry: DialogViewRegistry) {
        registry.register(ConsumerDialogViewModel.self) { _, notifier in
            notifier.complete("完了")
            return DialogTestContentView()
        }
    }
    #endif
}
#endif
