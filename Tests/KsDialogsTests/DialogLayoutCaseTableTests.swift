#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("レイアウト共通ケース表の全量検証", .serialized)
@MainActor
struct DialogLayoutCaseTableTests {
    @Test("ケース表が読み込めている")
    func caseTableIsLoaded() {
        let table = DialogLayoutCaseLoader.table
        #expect(table.cases.isEmpty == false, "ケース表が空では検証にならない: \(DialogLayoutCaseLoader.caseTableURL.path)")
        #expect(table.tolerance > 0)
    }

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
        let actual = DialogLayoutMeasurement.measureContentFrame(
            contentView: contentView,
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
}
#endif
