#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// Toast の器を実際の window へ重ね、レイアウト完了後の中身の矩形を測る。
/// rect 計算だけを確かめても制約への反映漏れは見つからないため、器ごとに実測する (core/ADR-0009)。
@MainActor
enum ToastLayoutMeasurement {
    /// 器を window へ重ね、その状態でのレイアウトパスまで進める。
    /// window を隠すと表示状態が終わるため、呼び出し側が使い終わるまで保持して自分で隠す。
    /// - Parameters:
    ///   - contentView: Toast の中身 (メタ属性は添付で供給する)
    ///   - showPlacement: 表示 API の引数で渡す配置。nil なら添付が使われる
    ///   - fallbackPlacement: show 引数も添付も無いときに採る配置
    ///   - screen: window の大きさ
    ///   - insets: システム領域が占める4辺の余白
    static func layoutInWindow(
        contentView: UIView,
        showPlacement: DialogPlacement? = nil,
        fallbackPlacement: DialogPlacement = ToastPlacementDefault.placement,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) -> (container: ToastContainerViewController, window: DialogLayoutTestWindow) {
        let window = DialogLayoutTestWindow(
            frame: CGRect(x: 0, y: 0, width: screen.w, height: screen.h)
        )
        window.simulatedSafeAreaInsets = UIEdgeInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
        window.rootViewController = UIViewController()
        window.isHidden = false

        let container = ToastContainerViewController(
            content: DialogContent(view: contentView),
            placement: showPlacement,
            fallbackPlacement: fallbackPlacement
        )
        container.attach(to: window)
        return (container, window)
    }

    /// レイアウト完了後の中身の矩形 (window 座標)。
    static func measureContentFrame(
        contentView: UIView,
        showPlacement: DialogPlacement? = nil,
        fallbackPlacement: DialogPlacement = ToastPlacementDefault.placement,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) -> CGRect {
        let stage = layoutInWindow(
            contentView: contentView,
            showPlacement: showPlacement,
            fallbackPlacement: fallbackPlacement,
            screen: screen,
            insets: insets
        )
        defer { stage.window.isHidden = true }
        return contentView.frame
    }
}
#endif
