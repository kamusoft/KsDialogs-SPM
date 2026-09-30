#if canImport(UIKit)
import UIKit

/// ステータスバーのアイコンを明るい地向け (暗い色) に指定している提示元の画面。
@MainActor
final class StatusBarDarkContentTestViewController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
}
#endif
