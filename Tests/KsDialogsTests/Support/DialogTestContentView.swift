#if canImport(UIKit)
import UIKit

/// ダイアログの中身として使う最小の View。
final class DialogTestContentView: UIView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: 240, height: 120)
    }
}
#endif
