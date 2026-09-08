#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// Loading の取り付け先をテストが用意した View で供給する。
/// 取り付け先を持たない状態にすると「表示が成立しない環境」を再現できる。
@MainActor
final class LoadingTestPresentationSurface: LoadingPresentationSurface {
    var hostView: UIView?

    init(hostView: UIView?) {
        self.hostView = hostView
    }
}
#endif
