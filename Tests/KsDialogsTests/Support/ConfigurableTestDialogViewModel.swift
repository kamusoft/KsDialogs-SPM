@testable import KsDialogs

/// configure から状態を設定できる ViewModel。真偽値の結果を宣言する。
/// 状態の変更は UI スレッドに限るため MainActor に閉じる。
@MainActor
final class ConfigurableTestDialogViewModel: DialogViewModel {
    typealias Result = Bool

    /// 中身の生成時に読まれるメッセージ。configure で設定する。
    var message: String

    nonisolated init(message: String = "既定") {
        self.message = message
    }
}
