@testable import KsDialogs

/// View factory を登録しない ViewModel。未登録の経路を確認するために使う。
final class UnregisteredTestDialogViewModel: DialogViewModel {
    typealias Result = Bool
}
