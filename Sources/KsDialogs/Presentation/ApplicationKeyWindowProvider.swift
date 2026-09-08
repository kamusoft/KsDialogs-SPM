#if canImport(UIKit)
import UIKit

/// 前面でアクティブなシーンの key window をアプリケーションから取得する既定の供給元。
final class ApplicationKeyWindowProvider: DialogKeyWindowProvider {
    @MainActor
    var keyWindow: UIWindow? {
        let snapshots = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map {
                DialogWindowSceneSnapshot(
                    isForegroundActive: $0.activationState == .foregroundActive,
                    windows: $0.windows
                )
            }
        return Self.selectKeyWindow(from: snapshots)
    }

    /// 提示起点にできる window を選ぶ。
    /// 前面でアクティブなシーンの key window だけを採用し、無ければ nil を返す
    /// (背面・非アクティブのシーンや key でない window へ重ねると、利用者から見えない場所に出てしまう)。
    @MainActor
    static func selectKeyWindow(from snapshots: [DialogWindowSceneSnapshot]) -> UIWindow? {
        snapshots
            .filter(\.isForegroundActive)
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
#endif
