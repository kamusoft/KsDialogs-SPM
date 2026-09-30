#if canImport(UIKit)
import UIKit

/// 共通ケース表の `pageArea` を「表示中のページの safe area」として再現する view controller。
///
/// View はウィンドウ全体に広げ、バーの下まで伸びる UIKit 標準のページと同じ形にする。
/// そのうえで追加の safe area をページの外側の帯ぶんだけ与え、safe area の内側が
/// `pageArea` とシステム領域の内側の共通部分になるようにする。
final class DialogLayoutPageHostViewController: UIViewController {
    /// - Parameters:
    ///   - pageArea: ページの View の矩形 (ウィンドウ座標)
    ///   - screen: ウィンドウの大きさ
    ///   - insets: ウィンドウのシステム領域が占める4辺の余白 (ウィンドウの safe area)
    init(pageArea: DialogLayoutCase.Rect, screen: DialogLayoutCase.Size, insets: DialogLayoutCase.Insets) {
        super.init(nibName: nil, bundle: nil)
        // ウィンドウの safe area に上乗せされるので、システム領域より外側へはみ出す分だけを足す。
        additionalSafeAreaInsets = UIEdgeInsets(
            top: max(0, pageArea.y - insets.top),
            left: max(0, pageArea.x - insets.left),
            bottom: max(0, (screen.h - pageArea.y - pageArea.h) - insets.bottom),
            right: max(0, (screen.w - pageArea.x - pageArea.w) - insets.right)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("storyboard からの生成は使わない")
    }
}
#endif
