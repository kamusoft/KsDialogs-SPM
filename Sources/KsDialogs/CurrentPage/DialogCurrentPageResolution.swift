#if canImport(UIKit)
import CoreGraphics

/// 取得元を優先順に辿った結果。
enum DialogCurrentPageResolution: Equatable {
    /// ページの基準矩形 (提示先ウィンドウの座標)。
    case resolved(CGRect)

    /// どの取得元からもページが得られなかった。辿った順の理由を持つ。
    case unresolved(reasons: [String])

    /// 未解決のときに出す診断ログの本文。
    static func diagnosticMessage(reasons: [String]) -> String {
        "The current page could not be resolved, so the visible area is used instead. "
            + reasons.joined(separator: " ")
    }
}
#endif
