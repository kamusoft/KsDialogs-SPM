#if canImport(UIKit)

/// 窓全体を基準に片側の端へ付けた軸で、器が付いた側。
///
/// 向きは物理の向きで表し、書字方向に左右されない。前端は左 / 上、後端は右 / 下である。
/// 中身がその軸で安全領域の内側に収まらないときは、付いた側と反対の辺 (内側の辺) にそろえて置く。
enum DialogAnchoredEdge: Equatable, Sendable {
    /// 前端 (左 / 上) に付いた。内側の辺は後端 (右 / 下)。
    case leadingEdge
    /// 後端 (右 / 下) に付いた。内側の辺は前端 (左 / 上)。
    case trailingEdge
}
#endif
