#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 表示中にウィンドウの寸法・可視領域の余白が変わったときの追随を確かめる。
///
/// 実効値は器を画面に載せたあとの初回レイアウトパスで固定されており (core/ADR-0015)、
/// 寸法が変わっても固定済みの属性のまま新しい寸法・余白で配置し直される。
/// ソフトキーボードによる余白の変化ではダイアログを動かさないため、ここでは扱わない。
@Suite("表示中のウィンドウ変化への追随", .serialized)
@MainActor
struct DialogWindowChangeTests {
    /// 縦向きのウィンドウ (システム領域は上下)。
    private static let portraitScreen = DialogLayoutCase.Size(w: 390, h: 844)
    private static let portraitInsets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)

    /// 横向きのウィンドウ (システム領域は左右と下)。
    private static let landscapeScreen = DialogLayoutCase.Size(w: 844, h: 390)
    private static let landscapeInsets = DialogLayoutCase.Insets(top: 0, bottom: 21, left: 59, right: 59)

    @Test("[PB-WN-01] 回転後も配置規則が新しい寸法で成立する")
    func PB_WN_01_rotationRelayoutsWithNewBounds() async throws {
        let stage = try makeStage()
        defer { stage.window.isHidden = true }

        // 縦向き: R = 390 x (844 - 59 - 34) = 390 x 751、A は各辺 24 控除、比率は R 基準。
        expectContentFrame(stage.contentView, x: 97.5, y: 340.625, width: 195, height: 187.75)

        // 固定後に添付を書き換えても、回転後の再配置は固定済みの値で行われる。
        stage.contentView.ksDialogOptions = DialogOptions(
            layoutArea: .window,
            dialogMargin: .zero,
            proportionalWidth: 0.9,
            proportionalHeight: 0.9
        )
        stage.window.changeGeometry(screen: Self.landscapeScreen, insets: Self.landscapeInsets)

        // 横向き: R = (844 - 118) x (390 - 21) = 726 x 369。
        expectContentFrame(stage.contentView, x: 240.5, y: 138.375, width: 363, height: 92.25)
        #expect(stage.container.isLayoutSnapshotFrozen, "実効値の固定は解けない")
    }

    @Test("[PB-WN-02] ウィンドウ寸法のみの変化に追随する")
    func PB_WN_02_boundsOnlyChangeRelayouts() async throws {
        let stage = try makeStage()
        defer { stage.window.isHidden = true }

        // 余白は据え置きで幅だけを狭める (マルチウィンドウのリサイズに相当)。
        stage.window.changeGeometry(
            screen: DialogLayoutCase.Size(w: 320, h: 844),
            insets: Self.portraitInsets
        )

        // 幅は新しい R (320) から導かれ、垂直方向は変わらない。
        expectContentFrame(stage.contentView, x: 80, y: 340.625, width: 160, height: 187.75)
    }

    @Test("[PB-WN-03] 可視領域インセットのみの変化に追随する")
    func PB_WN_03_insetsOnlyChangeRelayouts() async throws {
        let stage = try makeStage()
        defer { stage.window.isHidden = true }

        // 寸法は据え置きでシステム領域の余白だけを無くす。
        stage.window.changeGeometry(
            screen: Self.portraitScreen,
            insets: DialogLayoutCase.Insets(top: 0, bottom: 0, left: 0, right: 0)
        )

        // 基準領域は visibleArea なので、垂直方向が新しい余白から導き直される。
        expectContentFrame(stage.contentView, x: 97.5, y: 316.5, width: 195, height: 211)
    }

    // MARK: 組み立て

    private struct Stage {
        let container: DialogContainerViewController
        let window: DialogLayoutTestWindow
        let contentView: UIView
    }

    /// 比率サイズ・中央配置の属性を添付したダイアログを縦向きのウィンドウへ載せる。
    /// 比率と余白の両方が効く属性にすることで、寸法と余白のどちらの変化も rect に現れる。
    private func makeStage() throws -> Stage {
        let contentView = FixedContentSizeView(contentSize: CGSize(width: 100, height: 100))
        contentView.ksDialogOptions = DialogOptions(
            layoutArea: .visibleArea,
            dialogMargin: DialogEdgeInsets(all: 24),
            proportionalWidth: 0.5,
            proportionalHeight: 0.25
        )
        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.portraitScreen,
            insets: Self.portraitInsets
        )
        let window = try #require(stage.window as? DialogLayoutTestWindow)
        try #require(stage.container.isLayoutSnapshotFrozen, "実効値が固定される前では追随を観察できない")
        return Stage(container: stage.container, window: window, contentView: contentView)
    }

    /// 中身の矩形が期待値と一致することを、共通ケース表と同じ許容差で確かめる。
    private func expectContentFrame(
        _ contentView: UIView,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let tolerance = DialogLayoutCaseLoader.table.tolerance
        let actual = contentView.frame
        let detail = "期待 (x \(x), y \(y), w \(width), h \(height)) 実測 \(actual)"
        #expect(abs(Double(actual.minX) - x) <= tolerance, "x が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(Double(actual.minY) - y) <= tolerance, "y が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(Double(actual.width) - width) <= tolerance, "w が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(
            abs(Double(actual.height) - height) <= tolerance,
            "h が一致しない — \(detail)",
            sourceLocation: sourceLocation
        )
    }
}
#endif
