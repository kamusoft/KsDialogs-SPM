#if canImport(UIKit)
import UIKit

/// システム領域の余白を指定した値として振る舞う window。
/// 共通ケース表は環境差を期待値の分岐ではなく insets の入力差で表すため、
/// 実機の safe area ではなくケースが与えた値でレイアウトさせる。
final class DialogLayoutTestWindow: UIWindow {
    var simulatedSafeAreaInsets: UIEdgeInsets = .zero

    override var safeAreaInsets: UIEdgeInsets {
        simulatedSafeAreaInsets
    }

    /// 載せている器はそのままに、ウィンドウの寸法と可視領域の余白だけを変えて
    /// その状態でのレイアウトパスを走らせる。
    /// 回転・マルチウィンドウのリサイズ・システムバーの出入りに相当する状況を作れる。
    func changeGeometry(screen: DialogLayoutCase.Size, insets: DialogLayoutCase.Insets) {
        simulatedSafeAreaInsets = UIEdgeInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
        frame = CGRect(x: 0, y: 0, width: screen.w, height: screen.h)
        if let rootView = rootViewController?.view {
            // 差し替えた余白は、載っている View の可視領域へそのままでは伝わらない。
            // 一度違う寸法でレイアウトしてから目的の寸法へ戻し、UIKit に可視領域を
            // 計算し直させてから最後のパスを走らせる。
            rootView.frame = bounds.insetBy(dx: 0, dy: -1)
            layoutIfNeeded()
            rootView.frame = bounds
            rootView.setNeedsLayout()
        }
        setNeedsLayout()
        layoutIfNeeded()
    }
}
#endif
