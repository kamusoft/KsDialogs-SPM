@testable import KsDialogs

/// 既定のレジストリを共有する経路の確認に使う ViewModel。
/// 他のテストと干渉しないよう、この型はレジストリ共有のテストからのみ登録する。
final class SharedRegistryTestDialogViewModel: DialogViewModel {
    typealias Result = Bool
}
