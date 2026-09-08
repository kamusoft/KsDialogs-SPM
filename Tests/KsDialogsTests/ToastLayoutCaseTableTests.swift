#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// レイアウト共通ケース表を Toast の器で全量回す (core/ADR-0009・core/ADR-0030)。
///
/// レイアウト規則は Dialog / Loading と共有する部品を通るが、器が変われば制約への反映漏れの形も
/// 変わるため、器ごとに実測する。表は Dialog の器と同じ1つの正 (`core/layout-spec/cases.json`) を使う。
/// 覆い・外側タップに関わる観察は Toast では対象外に読み替える (どちらも存在しない)。
/// Toast の契約既定配置は表の C23 が受け持ち、そこでは実効値を添付として与えて検証する。
@Suite("Toast 器のレイアウト共通ケース表の全量検証", .serialized)
@MainActor
struct ToastLayoutCaseTableTests {
    @Test(
        "レイアウト完了後の実 frame が期待 rect に一致する",
        arguments: DialogLayoutCaseLoader.table.cases
    )
    func actualFrameMatchesExpectedRect(layoutCase: DialogLayoutCase) {
        let contentView = FixedContentSizeView(
            contentSize: CGSize(width: layoutCase.contentSize.w, height: layoutCase.contentSize.h)
        )
        // ケース表の attributes は供給を合成した後の実効値なので、添付だけで与えれば足りる。
        contentView.ksDialogOptions = layoutCase.attributes.options
        contentView.ksDialogPlacement = layoutCase.attributes.placement
        let actual = ToastLayoutMeasurement.measureContentFrame(
            contentView: contentView,
            fallbackPlacement: DialogPlacement(),
            screen: layoutCase.screen,
            insets: layoutCase.insets
        )

        let tolerance = DialogLayoutCaseLoader.table.tolerance
        let expected = layoutCase.expected
        let detail = "\(layoutCase.id): 期待 (x \(expected.x), y \(expected.y), w \(expected.w), h \(expected.h)) 実測 \(actual)"
        #expect(abs(Double(actual.minX) - expected.x) <= tolerance, "x が一致しない — \(detail)")
        #expect(abs(Double(actual.minY) - expected.y) <= tolerance, "y が一致しない — \(detail)")
        #expect(abs(Double(actual.width) - expected.w) <= tolerance, "w が一致しない — \(detail)")
        #expect(abs(Double(actual.height) - expected.h) <= tolerance, "h が一致しない — \(detail)")
    }

    @Test("契約既定配置で表示した Toast が共通ケース表の C23 と同じ位置に置かれる")
    func contractDefaultPlacementMatchesCaseTable() throws {
        let layoutCase = try #require(
            DialogLayoutCaseLoader.table.cases.first { $0.id == "C23" },
            "共通ケース表に Toast の契約既定配置のケースが無い"
        )
        let contentView = FixedContentSizeView(
            contentSize: CGSize(width: layoutCase.contentSize.w, height: layoutCase.contentSize.h)
        )
        // 添付も show 引数も与えず、契約既定値だけで置かれることを見る。
        let actual = ToastLayoutMeasurement.measureContentFrame(
            contentView: contentView,
            screen: layoutCase.screen,
            insets: layoutCase.insets
        )

        let tolerance = DialogLayoutCaseLoader.table.tolerance
        let expected = layoutCase.expected
        #expect(abs(Double(actual.minX) - expected.x) <= tolerance, "x が一致しない — 実測 \(actual)")
        #expect(abs(Double(actual.minY) - expected.y) <= tolerance, "y が一致しない — 実測 \(actual)")
    }
}
#endif
