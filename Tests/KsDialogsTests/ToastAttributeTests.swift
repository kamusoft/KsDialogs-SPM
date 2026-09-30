#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Toast の配置属性と `ToastStyle` の契約 (core/ADR-0032) を確かめる。
///
/// 配置の優先順は「show 引数 > 中身への添付 > style のアプリ既定配置 > 契約既定値」で、
/// placement はオブジェクトまるごと置換で採用される。
/// style は各表示の受理時に読まれるため、設定の変更は次の表示から効く。
@Suite("Toast の配置属性と ToastStyle", .serialized, .awaitsMainActorResponsive)
@MainActor
struct ToastAttributeTests {
    /// 観察の途中で期限が来ないだけの長さ。
    private static let longDuration = 5000

    /// デフォルト View が自分に添付している余白 (全辺)。
    private static let defaultViewMargin: CGFloat = 24

    /// 1 行では可視領域の幅に収まらない長さの、禁則の掛からない仮名だけのメッセージ。
    private static let wrappingKanaMessage = String(repeating: "あいうえおかきくけこ", count: 4)

    /// 可視領域の下端 (取り付け先の座標)。
    private static var visibleBottom: CGFloat {
        ToastTestHarness.portraitScreen.h - ToastTestHarness.portraitInsets.bottom
    }

    @Test("[TS-AT-01] placement 引数で配置が変わる")
    func TS_AT_01_placementArgumentChangesPosition() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        harness.toast.show(message: "既定の位置", duration: Self.longDuration)
        try #require(await harness.waitUntilPresenting())
        harness.window.layoutIfNeeded()
        let defaultFrame = try #require(harness.contentViews.first).frame

        let topHarness = ToastTestHarness()
        defer { topHarness.tearDown() }
        topHarness.toast.show(
            message: "上端の位置",
            duration: Self.longDuration,
            placement: DialogPlacement(verticalAlignment: .start)
        )
        try #require(await topHarness.waitUntilPresenting())
        topHarness.window.layoutIfNeeded()
        let placedFrame = try #require(topHarness.contentViews.first).frame

        #expect(placedFrame.minY < defaultFrame.minY, "引数の配置がレイアウト規則どおりに効く")
        #expect(
            abs(placedFrame.minY - (ToastTestHarness.portraitInsets.top + Self.defaultViewMargin)) <= 1,
            "可視領域 + デフォルト View の余白の上端に置かれる"
        )
    }

    @Test("[TS-AT-02] 優先順は show 引数 > 添付 > style 既定 > 契約既定")
    func TS_AT_02_placementPrecedence() async throws {
        let attachedPlacement = DialogPlacement(verticalAlignment: .start)
        let stylePlacement = DialogPlacement(verticalAlignment: .center)
        let argumentPlacement = DialogPlacement(verticalAlignment: .end)

        // 添付のみ: 添付値が採用される。
        let attachedOnly = ToastTestHarness()
        defer { attachedOnly.tearDown() }
        attachedOnly.toast.style = ToastStyle(defaultPlacement: stylePlacement)
        try attachedOnly.toast.show(ToastTestViewModel(), duration: Self.longDuration) { _ in
            let view = FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
            view.ksDialogPlacement = attachedPlacement
            return view
        }
        try #require(await attachedOnly.waitUntilPresenting())
        attachedOnly.window.layoutIfNeeded()
        let attachedFrame = try #require(attachedOnly.contentViews.first).frame
        // カスタム View は余白を添付していないので、余白の既定値 0 で可視領域の上端に接する。
        #expect(
            abs(attachedFrame.minY - ToastTestHarness.portraitInsets.top) <= 1,
            "style のアプリ既定配置より添付が優先される"
        )

        // style のみ (デフォルト View): style のアプリ既定配置が採用される。
        let styleOnly = ToastTestHarness()
        defer { styleOnly.tearDown() }
        styleOnly.toast.style = ToastStyle(defaultPlacement: stylePlacement)
        styleOnly.toast.show(message: "style 既定", duration: Self.longDuration)
        try #require(await styleOnly.waitUntilPresenting())
        styleOnly.window.layoutIfNeeded()
        let styleFrame = try #require(styleOnly.contentViews.first).frame
        let visibleCenterY = ToastTestHarness.portraitInsets.top
            + (ToastTestHarness.portraitScreen.h
                - ToastTestHarness.portraitInsets.top
                - ToastTestHarness.portraitInsets.bottom) / 2
        #expect(abs(styleFrame.midY - visibleCenterY) <= 1, "style のアプリ既定配置が採用される")

        // show 引数つき: 引数がまるごと置換で採用される。
        let withArgument = ToastTestHarness()
        defer { withArgument.tearDown() }
        withArgument.toast.style = ToastStyle(defaultPlacement: stylePlacement)
        try withArgument.toast.show(
            ToastTestViewModel(),
            duration: Self.longDuration,
            placement: argumentPlacement
        ) { _ in
            let view = FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
            view.ksDialogPlacement = attachedPlacement
            return view
        }
        try #require(await withArgument.waitUntilPresenting())
        withArgument.window.layoutIfNeeded()
        let argumentFrame = try #require(withArgument.contentViews.first).frame
        let visibleBottom = ToastTestHarness.portraitScreen.h
            - ToastTestHarness.portraitInsets.bottom
        #expect(
            abs(argumentFrame.maxY - visibleBottom) <= 1,
            "引数の配置が添付も style も置換する"
        )
    }

    @Test("[TS-AT-03] style の変更は次の表示から効く")
    func TS_AT_03_styleChangeAppliesToNextDisplayOnly() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        harness.toast.style = ToastStyle(textColor: .white, fontSize: 14)

        harness.toast.show(message: "先の表示", duration: Self.longDuration)
        try #require(await harness.waitUntilPresenting())
        let first = try #require(harness.defaultContentViews.first)

        harness.toast.style = ToastStyle(textColor: .red, fontSize: 24)
        harness.toast.show(message: "後の表示", duration: Self.longDuration)
        try #require(await harness.waitUntilPresenting(count: 2))
        let second = try #require(harness.defaultContentViews.last)

        #expect(first.displayedFont.pointSize == 14, "表示中の Toast は変わらない")
        #expect(first.displayedTextColor == .white)
        #expect(second.displayedFont.pointSize == 24, "新しい Toast にだけ変更後の style が効く")
        #expect(second.displayedTextColor == .red)
    }

    @Test("[TS-AT-04] デフォルト View は契約既定配置で余白 24 の内側に置かれる")
    func TS_AT_04_defaultViewSitsInsideItsMarginAtContractDefaultPlacement() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        harness.toast.show(message: "既定の位置", duration: Self.longDuration)
        try #require(await harness.waitUntilPresenting())
        harness.window.layoutIfNeeded()
        let frame = try #require(harness.defaultContentViews.first).frame

        let expectedBottom = Self.visibleBottom - Self.defaultViewMargin - CGFloat(ToastPlacementDefault.bottomBarClearance)
        #expect(
            abs(frame.maxY - expectedBottom) <= 1,
            "下端は可視領域の下端から余白 24 + 上方向オフセットだけ上にある (実測 \(frame))"
        )
    }

    @Test("[TS-AT-05] 長いメッセージでもデフォルト View の左右に余白 24 が残る")
    func TS_AT_05_longMessageKeepsHorizontalMarginOfDefaultView() async throws {
        // 左右のシステム領域で可視領域を 190 まで狭める。余白を引いた幅 (142) が
        // デフォルト View 自身の最大幅 (取り付け先 390 の 80% = 312) より狭くなり、余白の制約が先に効く。
        // 余白の添付が無ければ、ピルは可視領域の左右の端 (100 / 290) まで広がる。
        let insets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 100, right: 100)
        let harness = ToastTestHarness(insets: insets)
        defer { harness.tearDown() }

        harness.toast.show(message: Self.wrappingKanaMessage, duration: Self.longDuration)
        try #require(await harness.waitUntilPresenting())
        harness.window.layoutIfNeeded()
        let frame = try #require(harness.defaultContentViews.first).frame

        // ピルは折り返した行の幅に縮むため、行の幅が余白の内側の幅に満たない余り (1 字幅未満) が
        // 左右に等分される。文言は禁則の掛からない仮名だけにして、行が字幅の整数倍で埋まるようにしてある。
        let glyphWidth = ("あ" as NSString).size(
            withAttributes: [.font: UIFont.systemFont(ofSize: CGFloat(ToastStyle().fontSize))]
        ).width
        let allowance = glyphWidth / 2 + 1
        let expectedLeft = insets.left + Self.defaultViewMargin
        let expectedRight = ToastTestHarness.portraitScreen.w - insets.right - Self.defaultViewMargin
        #expect(
            frame.minX >= expectedLeft - 1 && frame.minX <= expectedLeft + allowance,
            "左端は可視領域の左端から 24 内側にある (期待 \(expectedLeft)、実測 \(frame))"
        )
        #expect(
            frame.maxX <= expectedRight + 1 && frame.maxX >= expectedRight - allowance,
            "右端は可視領域の右端から 24 内側にある (期待 \(expectedRight)、実測 \(frame))"
        )
    }

    @Test("[TS-AT-06] 配置を渡してもデフォルト View の余白は保たれる")
    func TS_AT_06_defaultViewKeepsMarginUnderSuppliedPlacement() async throws {
        let topPlacement = DialogPlacement(verticalAlignment: .start)
        let expectedTop = ToastTestHarness.portraitInsets.top + Self.defaultViewMargin

        // show の placement 引数で渡す。
        let withArgument = ToastTestHarness()
        defer { withArgument.tearDown() }
        withArgument.toast.show(message: "引数の配置", duration: Self.longDuration, placement: topPlacement)
        try #require(await withArgument.waitUntilPresenting())
        withArgument.window.layoutIfNeeded()
        let argumentFrame = try #require(withArgument.defaultContentViews.first).frame
        #expect(
            abs(argumentFrame.minY - expectedTop) <= 1,
            "show 引数の配置でも上端は可視領域の上端から 24 内側にある (実測 \(argumentFrame))"
        )

        // ToastStyle のアプリ既定配置に設定して、配置なしで出す。
        let withStyle = ToastTestHarness()
        defer { withStyle.tearDown() }
        withStyle.toast.style = ToastStyle(defaultPlacement: topPlacement)
        withStyle.toast.show(message: "style の配置", duration: Self.longDuration)
        try #require(await withStyle.waitUntilPresenting())
        withStyle.window.layoutIfNeeded()
        let styleFrame = try #require(withStyle.defaultContentViews.first).frame
        #expect(
            abs(styleFrame.minY - expectedTop) <= 1,
            "アプリ既定配置でも上端は可視領域の上端から 24 内側にある (実測 \(styleFrame))"
        )
    }

    @Test("[TS-AT-07] 何も添付しないカスタム View は余白 0 で契約既定配置に置かれる")
    func TS_AT_07_customViewWithoutAttachmentUsesZeroMargin() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        try harness.toast.show(ToastTestViewModel(), duration: Self.longDuration) { _ in
            FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
        }
        try #require(await harness.waitUntilPresenting())
        harness.window.layoutIfNeeded()
        let frame = try #require(harness.contentViews.first).frame

        let expectedBottom = Self.visibleBottom - CGFloat(ToastPlacementDefault.bottomBarClearance)
        #expect(
            abs(frame.maxY - expectedBottom) <= 1,
            "下端は可視領域の下端から上方向オフセットだけ上にある (実測 \(frame))"
        )
    }

    @Test("デフォルト View に ToastStyle の視覚項目が反映される")
    func defaultContentViewReflectsStyle() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        harness.toast.show(message: "既定の見え", duration: Self.longDuration)
        try #require(await harness.waitUntilPresenting())

        let contentView = try #require(harness.defaultContentViews.first)
        let style = ToastStyle()
        #expect(contentView.displayedBackgroundColor == style.backgroundColor)
        #expect(contentView.displayedTextColor == style.textColor)
        #expect(contentView.displayedFont.pointSize == CGFloat(style.fontSize))
        #expect(contentView.displayedCornerRadius == CGFloat(style.cornerRadius))
    }

    @Test("空文字のメッセージもそのまま表示され、長文は折り返して高さが伸びる")
    func defaultContentViewHandlesEmptyAndLongMessages() async throws {
        let empty = ToastTestHarness()
        defer { empty.tearDown() }
        empty.toast.show(message: "", duration: Self.longDuration)
        try #require(await empty.waitUntilPresenting())
        empty.window.layoutIfNeeded()
        let emptyFrame = try #require(empty.contentViews.first).frame
        #expect(emptyFrame.height > 0, "内容が空でもピルは表示される")

        let long = ToastTestHarness()
        defer { long.tearDown() }
        long.toast.show(
            message: String(repeating: "折り返しの確認をするための長いメッセージ。", count: 4),
            duration: Self.longDuration
        )
        try #require(await long.waitUntilPresenting())
        long.window.layoutIfNeeded()
        let longFrame = try #require(long.contentViews.first).frame
        #expect(longFrame.height > emptyFrame.height, "長文は複数行に折り返して高さが伸びる")
        #expect(
            longFrame.width <= ToastTestHarness.portraitScreen.w * 0.8 + 1,
            "幅は取り付け先の 80% で頭打ちになる"
        )
    }
}
#endif
