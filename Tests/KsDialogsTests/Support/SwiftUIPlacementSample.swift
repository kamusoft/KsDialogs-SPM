#if canImport(UIKit)
import CoreGraphics

/// ある瞬間の器の矩形と、中身に重ねた目印が描かれた矩形 (どちらも window 座標)。
struct SwiftUIPlacementSample {
    let container: CGRect
    /// 目印ごとの描かれた矩形。目印が window に載っていなければ nil。
    let drawn: [CGRect?]
}
#endif
