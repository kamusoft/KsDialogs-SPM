#if canImport(UIKit)
import CoreGraphics

/// 1軸 (水平 または 垂直) 分のレイアウト解。
/// 位置は基準 rect ではなくウィンドウの前端 (左 / 上) からの距離で表すため、
/// そのまま制約の定数として使える。
struct DialogAxisLayout {
    /// 軸方向の位置指定。内容サイズに委ねる場合でも一意に決まるよう、
    /// 前端・中央・後端のいずれを固定するかで表す。
    enum Position {
        /// 前端 (左 / 上) をこの位置に固定する。
        case leadingEdge(CGFloat)
        /// 中央をこの位置に固定する。
        case center(CGFloat)
        /// 後端 (右 / 下) をこの位置に固定する。
        case trailingEdge(CGFloat)

        /// 固定する位置の値。
        var constant: CGFloat {
            switch self {
            case .leadingEdge(let value), .center(let value), .trailingEdge(let value):
                return value
            }
        }
    }

    /// 決まったサイズ。nil なら内容サイズに委ねる。
    let size: CGFloat?

    /// 有効領域の軸長。どの決め方をしてもサイズはこの値で頭打ちになる。
    let maxSize: CGFloat

    /// 軸方向の位置。
    let position: Position
}
#endif
