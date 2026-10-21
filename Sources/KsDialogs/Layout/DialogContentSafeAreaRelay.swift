#if canImport(UIKit)

/// 器と安全領域の重なりを、軸ごとに中身へ渡すかどうかを器から受け取る面。
///
/// 中身の位置が端に固定される軸では、重なりを渡すと中身が器の内側で安全領域を避けられる。
/// 中央に固定される軸で渡すと、中身が重なりの分だけ大きさを求め直し、置き直すたびに重なりが
/// 増えて膨らむため渡さない。どの軸で渡すかはレイアウトの解から器が決め、この面へ伝える。
/// この面を持たない中身 (従来 View 系) には、UIKit の伝播どおりの safe area がそのまま届く。
@MainActor
protocol DialogContentSafeAreaRelay: AnyObject {
    /// 重なりを中身へ渡す軸を指定する。渡さない軸の辺は、中身から見て安全領域 0 になる。
    func relaySafeArea(horizontal: Bool, vertical: Bool)

    /// 窓全体を基準に片側の端へ付けた軸と、その軸で器が付いた側を指定する。
    ///
    /// 指定した軸で中身が安全領域の内側に収まらないときは、中身を付いた側と反対の辺 (内側の辺) に
    /// そろえ、器いっぱいまで使って置く。nil の軸 (両側の端・中央の軸、窓全体以外の基準領域) では
    /// 並び方を変えない。
    func anchorEdges(horizontal: DialogAnchoredEdge?, vertical: DialogAnchoredEdge?)
}
#endif
