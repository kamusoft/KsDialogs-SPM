#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("外側タップキャンセル", .serialized)
@MainActor
struct DialogOutsideTapTests {
    private static let screen = DialogLayoutCase.Size(w: 400, h: 800)
    private static let insets = DialogLayoutCase.Insets(top: 50, bottom: 30, left: 0, right: 0)
    private static let contentSize = CGSize(width: 280, height: 180)

    /// 中身の外側にあたる点 (中身は既定値では中央に置かれる)。
    private static let outsidePoint = CGPoint(x: 5, y: 5)

    @Test("既定では外側タップで cancelled が確定する")
    func outsideTapSettlesCancelledByDefault() {
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: resultChannel
        )

        container.reportOutsideTap()

        #expect(recorder.count == 1)
        #expect(recorder.isFirstCancelled)
    }

    @Test("覆いのタップは器が受け取り、中身の上のタップは対象外になる")
    func backdropTapIsRecognizedByContainer() throws {
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )

        container.loadViewIfNeeded()

        let recognizer = try #require(
            container.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first
        )
        #expect(recognizer.delegate === container, "中身の上のタップを除外する判定は器が持つ")
    }

    @Test("覆いの上の点は外側と判別し、中身の上の点は内側と判別する")
    func outsideTapPredicateSeparatesBackdropFromContent() async throws {
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.screen,
            insets: Self.insets
        )
        defer { stage.window.isHidden = true }
        try #require(await DialogLayoutMeasurement.waitUntilPresentationCompletes(stage.container))

        // 実際のタップと同じ経路 (座標 → ヒットテスト → 内外の判別述語) を通す。
        let touchedOutside = stage.container.view.hitTest(Self.outsidePoint, with: nil)
        let insidePoint = CGPoint(x: contentView.frame.midX, y: contentView.frame.midY)
        let touchedInside = stage.container.view.hitTest(insidePoint, with: nil)

        #expect(touchedOutside === stage.container.view, "覆いの上の点は覆いが受け取る")
        #expect(touchedInside === contentView, "中身の上の点は中身が受け取る")
        #expect(stage.container.isOutsideTap(touching: touchedOutside))
        #expect(stage.container.isOutsideTap(touching: touchedInside) == false)
    }

    @Test("中身の上のタップでは cancelled にならない")
    func tapOnContentDoesNotSettleCancelled() async throws {
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }

        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.screen,
            insets: Self.insets,
            resultChannel: resultChannel
        )
        defer { stage.window.isHidden = true }
        try #require(await DialogLayoutMeasurement.waitUntilPresentationCompletes(stage.container))

        // 中身の中心を触ったときはジェスチャ自体が成立しないため、器は結果を確定させない。
        let insidePoint = CGPoint(x: contentView.frame.midX, y: contentView.frame.midY)
        let touchedInside = stage.container.view.hitTest(insidePoint, with: nil)
        if stage.container.isOutsideTap(touching: touchedInside) {
            stage.container.reportOutsideTap()
        }

        let settled = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) {
            resultChannel.isResultSettled
        }
        #expect(settled == false, "ダイアログは表示されたまま")
        #expect(recorder.count == 0)
    }

    @Test("false なら外側タップは無反応で、タップは背後へ透過しない")
    func outsideTapDoesNothingWhenDisabled() async {
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        contentView.ksDialogOptions = DialogOptions(isCanceledOnTouchOutside: false)
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }

        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.screen,
            insets: Self.insets,
            resultChannel: resultChannel
        )
        defer { stage.window.isHidden = true }

        stage.container.reportOutsideTap()

        let settled = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) {
            resultChannel.isResultSettled
        }
        #expect(settled == false, "ダイアログは表示されたまま")
        #expect(recorder.count == 0)
        #expect(
            stage.container.view.hitTest(Self.outsidePoint, with: nil) === stage.container.view,
            "外側のタップは覆いが吸収し、背後の画面へは届かない"
        )
    }

    @Test("透明な覆いでも外側タップの扱いは変わらない")
    func outsideTapIsIndependentFromOverlayColor() {
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        contentView.ksDialogOptions = DialogOptions(overlayColor: .clear)
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }

        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.screen,
            insets: Self.insets,
            resultChannel: resultChannel
        )
        defer { stage.window.isHidden = true }

        #expect(
            stage.container.view.hitTest(Self.outsidePoint, with: nil) === stage.container.view,
            "透明でもタップは覆いが受け取る"
        )
        stage.container.reportOutsideTap()

        #expect(recorder.count == 1)
        #expect(recorder.isFirstCancelled)
    }
}
#endif
