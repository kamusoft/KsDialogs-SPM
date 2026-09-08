import Foundation

/// 共通ケース表の1ケース。
/// 「画面サイズ・システム領域の余白・内容サイズ・レイアウト属性 → 期待 rect」の組。
struct DialogLayoutCase: Decodable, Sendable, CustomStringConvertible {
    /// 幅と高さ。
    struct Size: Decodable, Sendable {
        let w: Double
        let h: Double
    }

    /// 4辺の余白。
    struct Insets: Decodable, Sendable {
        let top: Double
        let bottom: Double
        let left: Double
        let right: Double
    }

    /// 期待する矩形 (原点はウィンドウの左上)。
    struct Rect: Decodable, Sendable {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
    }

    let id: String
    let screen: Size
    let insets: Insets
    let contentSize: Size
    let attributes: DialogLayoutCaseAttributes
    let expected: Rect

    /// 失敗時にどのケースかが分かるよう ID を表示名にする。
    var description: String { id }
}
