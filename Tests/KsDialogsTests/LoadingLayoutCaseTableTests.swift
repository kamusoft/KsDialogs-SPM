#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// レイアウト共通ケース表を Loading の器で全量回す (core/ADR-0009・core/ADR-0022)。
///
/// レイアウト規則は Dialog と共有する部品を通るが、器が変われば制約への反映漏れの形も変わるため、
/// 器ごとに実測する。表は Dialog の器と同じ1つの正 (`core/layout-spec/cases.json`) を使う。
/// isCanceledOnTouchOutside に関わる観察は Loading では「常に無効」に読み替える
/// (表は同属性のケースを持たないため、読み替えは `LoadingAttributeTests` の LD-AT-03 が担う)。
@Suite("Loading 器のレイアウト共通ケース表の全量検証", .serialized)
@MainActor
struct LoadingLayoutCaseTableTests {
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
        let actual = LoadingLayoutMeasurement.measureContentFrame(
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
