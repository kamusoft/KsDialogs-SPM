#if canImport(UIKit)

/// 添付値の供給が中身の描画機構を経由して届く中身が、その到達を器へ知らせる面。
///
/// 宣言的 UI の中身は、添付値が器のレイアウトパスの中で初めて確定する。
/// 器はこの面を持つ中身に限り「まだ供給が届いていない」状態を区別し、
/// 追加のレイアウトパスを上限つきで待ってから実効値を固定する (core/ADR-0015)。
/// 従来 View 系の中身はこの面を持たないため、待ちは一切発生しない。
@MainActor
protocol DialogAttributeSupplyProbe {
    /// 添付値の供給が1度でも届いたか。
    var hasResolvedAttributeSupply: Bool { get }
}
#endif
