/// ダイアログを基準領域のどこへ寄せるか。
///
/// `start` / `end` は物理方向 (水平軸なら左 / 右、垂直軸なら上 / 下) を指し、
/// 書字方向 (RTL) には追随しない。
/// `fill` は位置だけでなくサイズも有効領域いっぱいに広げるが、
/// 比率サイズが指定されている軸ではサイズの決め方として採用されず、位置は中央になる。
public enum DialogAlignment: Sendable, Equatable {
    case start
    case center
    case end
    case fill
}
