#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 基準領域「表示中のページ」のテストで使う、ウィンドウ・器の組み立てと矩形の照合。
///
/// 寸法は共通ケース表と同じ縦長の画面 (400 x 800、上 50 / 下 30 のシステム領域) にそろえる。
/// 中身は内容サイズ 280 x 180 固定で、余白は契約既定の 0 を使う (core/ADR-0039)。
@MainActor
enum DialogCurrentPageStage {
    static let screen = DialogLayoutCase.Size(w: 400, h: 800)
    static let insets = DialogLayoutCase.Insets(top: 50, bottom: 30, left: 0, right: 0)
    static let contentSize = CGSize(width: 280, height: 180)
    static let margin: CGFloat = 0

    /// 右下 (水平・垂直とも End)。
    static let endEnd = DialogPlacement(horizontalAlignment: .end, verticalAlignment: .end)

    /// 左上 (水平・垂直とも Start)。
    static let startStart = DialogPlacement(horizontalAlignment: .start, verticalAlignment: .start)

    /// ウィンドウの可視領域 (システム領域の内側)。
    static var visibleRect: CGRect {
        CGRect(
            x: insets.left,
            y: insets.top,
            width: screen.w - insets.left - insets.right,
            height: screen.h - insets.top - insets.bottom
        )
    }

    /// root の view controller を載せた、ケース表と同じ寸法のウィンドウ。
    static func makeWindow(rootViewController: UIViewController) -> DialogLayoutTestWindow {
        DialogLayoutTestWindow.showing(rootViewController: rootViewController, screen: screen, insets: insets)
    }

    /// View の safe area の内側をウィンドウ座標で返す (ページとして使われる矩形)。
    static func safeAreaRect(of view: UIView) -> CGRect {
        view.convert(view.safeAreaLayoutGuide.layoutFrame, to: nil)
    }

    /// 中身に属性を添付したダイアログの器をウィンドウへ重ね、初回レイアウトまで進める。
    static func showDialog(
        in window: UIWindow,
        layoutArea: DialogLayoutArea = .currentPage,
        placement: DialogPlacement,
        proportionalHeight: Double = -1
    ) -> (container: DialogContainerViewController, contentView: UIView) {
        let contentView = FixedContentSizeView(contentSize: contentSize)
        contentView.ksDialogOptions = DialogOptions(layoutArea: layoutArea, proportionalHeight: proportionalHeight)
        contentView.ksDialogPlacement = placement
        let container = DialogContainerViewController(
            content: DialogContent(view: contentView),
            resultChannel: DialogResultChannel()
        )
        DialogLayoutMeasurement.attach(container, to: window)
        return (container, contentView)
    }

    /// 基準矩形の右下に End/End で置いたときの中身の矩形。
    static func endEndFrame(in base: CGRect) -> CGRect {
        CGRect(
            x: base.maxX - margin - contentSize.width,
            y: base.maxY - margin - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    /// 基準矩形の左上に Start/Start で置いたときの中身の矩形。
    static func startStartFrame(in base: CGRect) -> CGRect {
        CGRect(
            x: base.minX + margin,
            y: base.minY + margin,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    /// 中身の矩形が期待値と一致することを、共通ケース表と同じ許容差で確かめる。
    static func expectFrame(
        _ contentView: UIView,
        _ expected: CGRect,
        _ comment: String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let tolerance = DialogLayoutCaseLoader.table.tolerance
        let actual = contentView.frame
        let detail = "\(comment) 期待 \(expected) 実測 \(actual)"
        #expect(abs(actual.minX - expected.minX) <= tolerance, "x が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(actual.minY - expected.minY) <= tolerance, "y が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(actual.width - expected.width) <= tolerance, "w が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(actual.height - expected.height) <= tolerance, "h が一致しない — \(detail)", sourceLocation: sourceLocation)
    }
}
#endif
