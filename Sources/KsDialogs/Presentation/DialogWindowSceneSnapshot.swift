#if canImport(UIKit)
import UIKit

/// 提示起点の選択に使う、シーン1つ分の情報。
struct DialogWindowSceneSnapshot {
    /// そのシーンが前面でアクティブか。
    let isForegroundActive: Bool
    /// そのシーンが持つ window。
    let windows: [UIWindow]
}
#endif
