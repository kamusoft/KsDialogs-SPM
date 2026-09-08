#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// Toast の取り付け先をテストが用意した View で供給する。
/// 取り付け先を持たない状態にすると「提示環境が無い」状況を再現できる。
@MainActor
final class ToastTestPresentationSurface: ToastPresentationSurface {
    var hostView: UIView?

    init(hostView: UIView?) {
        self.hostView = hostView
    }
}
#endif
