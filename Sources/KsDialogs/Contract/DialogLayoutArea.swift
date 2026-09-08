/// サイズと位置の計算を行う基準領域。
///
/// 水平・垂直の両軸に効く (core/ADR-0008)。
public enum DialogLayoutArea: Sendable, Equatable {
    /// ダイアログを載せるウィンドウの全体。
    case window

    /// ウィンドウからシステムバーなどが占める余白 (safe area) を控除した可視領域。
    case visibleArea
}
