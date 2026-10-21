#if canImport(UIKit)
import CoreGraphics

/// 大きさを中身に委ねた幅の上限 (有効領域の幅) を、器から受け取る面。
///
/// 置かれた幅を覚えて要求サイズを求める中身は、上限が広がっても覚えた幅のままでは広がらない。
/// 器は上限を決めるたびにこの面へ知らせ、中身は上限が前より広がったときだけ覚えた幅を捨てる。
/// この面を持たない中身には知らせない。
@MainActor
protocol DialogContentWidthLimitReceiver: AnyObject {
    /// 幅を中身に委ねた軸の上限を知らせる。幅を器が決める (比率・fill) ときは nil。
    func contentSizedWidthLimitDidChange(_ limit: CGFloat?)
}
#endif
