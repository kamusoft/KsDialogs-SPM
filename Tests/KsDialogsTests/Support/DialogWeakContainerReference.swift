#if canImport(UIKit)

@testable import KsDialogs

/// 器を強く握らずに生存だけを観察するための弱参照。
/// 器への強参照をすべて落とした状態で配送が成立するかを確かめるテストで使う。
@MainActor
final class DialogWeakContainerReference {
    private weak var container: DialogContainerViewController?

    init(_ container: DialogContainerViewController) {
        self.container = container
    }

    /// 器が解放されたか。
    var isReleased: Bool {
        container == nil
    }
}
#endif
