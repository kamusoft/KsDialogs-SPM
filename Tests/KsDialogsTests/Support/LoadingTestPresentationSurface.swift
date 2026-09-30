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

    /// 提示先の出現の合図の発火口。`fireHostAppearance()` で合図を送る。
    let hostAppearance = DialogTestHostAppearanceSignal()

    func observeHostAppearance(
        _ handler: @escaping DialogHostAppearanceHandler
    ) -> DialogHostAppearanceRegistration {
        hostAppearance.observe(handler)
    }

    /// 提示先の出現の合図を送る (本番の window の key 化・シーンのアクティブ化に対応する)。
    func fireHostAppearance() {
        hostAppearance.fire()
    }
}
#endif
