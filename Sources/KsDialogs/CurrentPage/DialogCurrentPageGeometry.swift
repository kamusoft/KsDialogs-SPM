#if canImport(UIKit)
import UIKit

/// ページの View から基準矩形を求める。
///
/// 基準はその View の safe area の内側 (`safeAreaLayoutGuide.layoutFrame`)。UIKit の標準の画面では
/// ページの View がタブバーやナビゲーションバーの下まで伸びているため、View の矩形ではなく
/// safe area を採ることでバーを除いた領域になる (core/ADR-0038)。
@MainActor
enum DialogCurrentPageGeometry {
    /// View の safe area の内側を、提示先ウィンドウの座標で返す。
    /// - Parameters:
    ///   - view: ページとして得た View
    ///   - window: ダイアログを出すウィンドウ
    ///   - origin: 失敗理由の文に入れる取得元の呼び名
    static func pageRect(of view: UIView, in window: UIWindow, origin: String) -> DialogCurrentPageLookup {
        guard view.window === window else {
            return .notFound(reason: "The view from \(origin) is not in the window presenting the dialog.")
        }
        let rect = view.convert(view.safeAreaLayoutGuide.layoutFrame, to: window)
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0
        else {
            return .notFound(reason: "The safe area of the view from \(origin) is empty.")
        }
        guard rect.intersects(window.bounds) else {
            return .notFound(reason: "The view from \(origin) lies outside the window presenting the dialog.")
        }
        return .found(rect)
    }
}
#endif
