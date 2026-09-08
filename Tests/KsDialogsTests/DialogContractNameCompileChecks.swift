#if canImport(UIKit)
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// ダイアログ表示の契約型名のコンパイル検証。
///
/// 契約型名は `Ks` + 機能名の単数形で、Dialog / Loading / Toast が同じ規則で並ぶ。
/// 正の検証 (3 機能の契約型がその名前で解決でき、既定エントリがダイアログの契約に適合する) は
/// 既定のビルドに含まれる。負の検証はフラグを定義したビルドが失敗することが期待結果になる:
///
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_LEGACY_CONTRACT_NAME'
@MainActor
enum DialogContractNameCompileChecks {
    /// 3 機能の契約型が単数形の名前で解決でき、既定エントリがダイアログの契約に適合する。
    static func namesContractsInSingularForm(dialog: Dialog) {
        let dialogs: any KsDialog = dialog
        let contracts: [Any.Type] = [(any KsDialog).self, (any KsLoading).self, (any KsToast).self]
        _ = dialogs
        _ = contracts
    }

    #if KSDIALOGS_NEGATIVE_CHECK_LEGACY_CONTRACT_NAME
    /// ダイアログ表示の契約に `KsDialogs` という型名はない。
    /// 期待する診断: cannot find type 'KsDialogs' in scope
    static func rejectsLegacyContractName(dialogs: any KsDialogs) {
        _ = dialogs
    }
    #endif
}
#endif
