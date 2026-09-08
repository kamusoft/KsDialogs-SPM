/// 共通ケース表の全体。ケース一覧と座標比較の許容誤差を持つ。
struct DialogLayoutCaseTable: Decodable, Sendable {
    /// 数値の単位の説明 (iOS では pt)。
    let unit: String

    /// 座標比較の許容誤差。
    let tolerance: Double

    /// 全ケース。
    let cases: [DialogLayoutCase]
}
