#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// ダイアログの器を実際の window に載せ、レイアウト完了後の中身の矩形を測る。
/// rect 計算だけを確かめても制約への反映漏れは見つからないため、実測で確かめる (core/ADR-0009)。
@MainActor
enum DialogLayoutMeasurement {
    /// 器を window に載せて初回のレイアウトパスまで進める。
    /// window を隠すと表示状態が終わるため、呼び出し側が使い終わるまで保持して自分で隠す。
    /// - Parameters:
    ///   - contentView: ダイアログの中身 (メタ属性は添付で供給する)
    ///   - showPlacement: show の引数で渡す配置。nil なら添付が使われる
    ///   - screen: window の大きさ
    ///   - insets: システム領域が占める4辺の余白
    ///   - resultChannel: 器が結果を確定させる口 (外側タップの結果を観察するときに渡す)
    static func layoutInWindow(
        contentView: UIView,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets,
        resultChannel: DialogResultChannel = DialogResultChannel()
    ) -> (container: DialogContainerViewController, window: UIWindow) {
        layoutInWindow(
            content: DialogContent(view: contentView),
            showPlacement: showPlacement,
            screen: screen,
            insets: insets,
            resultChannel: resultChannel
        )
    }

    /// 内部表現 (SwiftUI のホストを伴う中身を含む) をそのまま器に載せて window へ出す。
    static func layoutInWindow(
        content: DialogContent,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets,
        resultChannel: DialogResultChannel = DialogResultChannel()
    ) -> (container: DialogContainerViewController, window: UIWindow) {
        let window = DialogLayoutTestWindow(
            frame: CGRect(x: 0, y: 0, width: screen.w, height: screen.h)
        )
        window.simulatedSafeAreaInsets = UIEdgeInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
        let container = DialogContainerViewController(
            content: content,
            resultChannel: resultChannel,
            placement: showPlacement
        )
        window.rootViewController = container
        window.isHidden = false

        window.layoutIfNeeded()
        // 実効値のスナップショットは window 搭載時の初回 on-screen パス完了で固定済み
        // (器のルート View の didMoveToWindow 起点。本番の present と同じ境界 / core/ADR-0015)。
        // prepareForPresentation は暫定サイズ計算のみを行い、固定には関与しない。
        container.prepareForPresentation(inBounds: window.bounds)
        return (container, window)
    }

    /// 出現の演出が終わって表示中になるまで待つ。
    ///
    /// 器は出現の演出を始めるところまで中身を見せず、演出の途中は中身の位置や大きさが
    /// 動いている最中でもある (core/ADR-0017)。ヒットテストのように「見えていて、
    /// 最終的な位置にある中身」を前提に観察するテストはここまで進めてから測る。
    static func waitUntilPresentationCompletes(_ container: DialogContainerViewController) async -> Bool {
        await DialogTestWaiting.waitUntil { container.containerState == .shown }
    }

    /// レイアウト完了後の中身の矩形 (window 座標)。
    static func measureContentFrame(
        contentView: UIView,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) -> CGRect {
        let stage = layoutInWindow(
            contentView: contentView,
            showPlacement: showPlacement,
            screen: screen,
            insets: insets
        )
        defer { stage.window.isHidden = true }
        return contentView.frame
    }
}
#endif
