#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("メタ属性を供給しないダイアログの既定値", .serialized)
@MainActor
struct DialogLayoutAttributeDefaultsTests {
    @Test("何も供給しない値オブジェクトが契約の既定値を持つ")
    func attributeObjectsCarryContractDefaults() {
        let options = DialogOptions()
        let placement = DialogPlacement()

        #expect(options.layoutArea == .visibleArea)
        #expect(options.dialogMargin == DialogEdgeInsets(all: 24))
        #expect(options.proportionalWidth == -1)
        #expect(options.proportionalHeight == -1)
        #expect(options.overlayColor == UIColor(white: 0, alpha: 0.4))
        #expect(options.isCanceledOnTouchOutside)
        #expect(placement.horizontalAlignment == .center)
        #expect(placement.verticalAlignment == .center)
        #expect(placement.offsetX == 0)
        #expect(placement.offsetY == 0)
    }

    @Test("添付のない View は供給なしとして扱われる")
    func contentViewWithoutAttachmentSuppliesNothing() {
        let contentView = DialogTestContentView()

        #expect(contentView.ksDialogOptions == nil)
        #expect(contentView.ksDialogPlacement == nil)
    }

    @Test("添付も show 引数もないダイアログの表示が既定値ケースの rect と一致する")
    func dialogWithoutAnySupplyMatchesDefaultCase() throws {
        // C19 は全属性が既定値のケースで、属性を持たない既存の呼び出しの見え方を固定している。
        let layoutCase = try #require(DialogLayoutCaseLoader.table.cases.first { $0.id == "C19" })
        let contentView = FixedContentSizeView(
            contentSize: CGSize(width: layoutCase.contentSize.w, height: layoutCase.contentSize.h)
        )
        let actual = DialogLayoutMeasurement.measureContentFrame(
            contentView: contentView,
            screen: layoutCase.screen,
            insets: layoutCase.insets
        )

        let tolerance = DialogLayoutCaseLoader.table.tolerance
        #expect(abs(Double(actual.minX) - layoutCase.expected.x) <= tolerance, "実測 \(actual)")
        #expect(abs(Double(actual.minY) - layoutCase.expected.y) <= tolerance, "実測 \(actual)")
        #expect(abs(Double(actual.width) - layoutCase.expected.w) <= tolerance, "実測 \(actual)")
        #expect(abs(Double(actual.height) - layoutCase.expected.h) <= tolerance, "実測 \(actual)")
    }

    @Test("必要なフィールドだけを設定した添付は残りが既定値になる")
    func partiallyConfiguredOptionsKeepDefaultsForTheRest() {
        var options = DialogOptions()
        options.proportionalWidth = 0.5

        #expect(options.proportionalWidth == 0.5)
        #expect(options.dialogMargin == DialogEdgeInsets(all: 24))
        #expect(options.layoutArea == .visibleArea)
        #expect(options.overlayColor == UIColor(white: 0, alpha: 0.4))
        #expect(options.isCanceledOnTouchOutside)
    }
}
#endif
