#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// テストが用意した window を提示起点として供給する。
/// window を持たない状態にすると「提示先が存在しない」状況を再現できる。
@MainActor
final class DialogTestKeyWindowProvider: DialogKeyWindowProvider {
    var keyWindow: UIWindow?

    init(keyWindow: UIWindow?) {
        self.keyWindow = keyWindow
    }
}
#endif
