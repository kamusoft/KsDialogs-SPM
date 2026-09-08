/// スライドの出入り口になる辺。
///
/// `leading` / `trailing` はレイアウト方向に追随し、右から左へ読む環境では左右が入れ替わる。
/// `top` / `bottom` は物理方向で、レイアウト方向の影響を受けない。
public enum DialogTransitionEdge: Sendable {
    case top
    case bottom
    case leading
    case trailing
}
