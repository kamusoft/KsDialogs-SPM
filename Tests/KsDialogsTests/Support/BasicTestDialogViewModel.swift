@testable import KsDialogs

/// メッセージ1個を持ち、真偽値の結果を宣言する最小の ViewModel。
final class BasicTestDialogViewModel: DialogViewModel {
    typealias Result = Bool

    let message: String

    init(message: String) {
        self.message = message
    }
}
