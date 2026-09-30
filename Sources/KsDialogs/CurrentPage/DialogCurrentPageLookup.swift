#if canImport(UIKit)
import CoreGraphics

/// 1 つの取得元に表示中のページを問い合わせた結果。
enum DialogCurrentPageLookup: Equatable {
    /// ページの基準矩形 (提示先ウィンドウの座標)。
    case found(CGRect)

    /// この取得元からはページが得られなかった。理由は診断ログにそのまま載る英語の 1 文。
    case notFound(reason: String)
}
#endif
