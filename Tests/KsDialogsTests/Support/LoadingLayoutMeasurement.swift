#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// Loading の器を実際の window へ重ね、レイアウト完了後の中身の矩形を測る。
/// rect 計算だけを確かめても制約への反映漏れは見つからないため、器ごとに実測する (core/ADR-0009)。
@MainActor
enum LoadingLayoutMeasurement {
    /// 器を window へ重ね、その状態でのレイアウトパスまで進める。
    /// window を隠すと表示状態が終わるため、呼び出し側が使い終わるまで保持して自分で隠す。
    /// - Parameters:
    ///   - contentView: Loading の中身 (メタ属性は添付で供給する)
    ///   - showPlacement: 表示 API の引数で渡す配置。nil なら添付が使われる
    ///   - screen: window の大きさ
    ///   - insets: システム領域が占める4辺の余白
    ///   - pageArea: 表示中のページの View の矩形。nil ならページを持たない画面にする
    static func layoutInWindow(
        contentView: UIView,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets,
        pageArea: DialogLayoutCase.Rect? = nil
    ) -> (container: LoadingContainerViewController, window: DialogLayoutTestWindow) {
        let window = DialogLayoutTestWindow(
            frame: CGRect(x: 0, y: 0, width: screen.w, height: screen.h)
        )
        window.simulatedSafeAreaInsets = UIEdgeInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
        if let pageArea {
            // 器が載った瞬間の初回パスがページの safe area を読めるよう、先にページをレイアウトしておく。
            window.rootViewController = DialogLayoutPageHostViewController(
                pageArea: pageArea,
                screen: screen,
                insets: insets
            )
            window.isHidden = false
            window.layoutIfNeeded()
        } else {
            window.rootViewController = UIViewController()
            window.isHidden = false
        }

        let container = LoadingContainerViewController(
            content: DialogContent(view: contentView),
            placement: showPlacement
        )
        // Loading は提示スタックに載せず、取り付け先の View へ直接重ねる (core/ADR-0022)。
        container.attach(to: window)
        return (container, window)
    }

    /// レイアウト完了後の中身の矩形 (window 座標)。
    static func measureContentFrame(
        contentView: UIView,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets,
        pageArea: DialogLayoutCase.Rect? = nil
    ) -> CGRect {
        let stage = layoutInWindow(
            contentView: contentView,
            showPlacement: showPlacement,
            screen: screen,
            insets: insets,
            pageArea: pageArea
        )
        defer { stage.window.isHidden = true }
        return contentView.frame
    }
}
#endif
