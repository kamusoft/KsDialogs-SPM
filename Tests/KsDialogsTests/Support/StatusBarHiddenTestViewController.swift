#if canImport(UIKit)
import UIKit

/// ステータスバーを非表示にしている提示元の画面。
@MainActor
final class StatusBarHiddenTestViewController: UIViewController {
    override var prefersStatusBarHidden: Bool { true }
}
#endif
