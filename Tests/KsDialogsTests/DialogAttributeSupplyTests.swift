#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("メタ属性の供給と優先順位", .serialized)
@MainActor
struct DialogAttributeSupplyTests {
    /// 400 × 800 のウィンドウ。期待値は軸別レイアウト規則から導いてある。
    private static let screen = DialogLayoutCase.Size(w: 400, h: 800)
    private static let insets = DialogLayoutCase.Insets(top: 50, bottom: 30, left: 0, right: 0)
    private static let contentSize = CGSize(width: 280, height: 180)

    /// ウィンドウ全体を基準にし余白を持たない静的メタ属性。
    /// 期待値の導出を単純にするため、供給経路そのものを見たいテストではこれを土台にする。
    private static func plainOptions() -> DialogOptions {
        DialogOptions(layoutArea: .window, dialogMargin: .zero)
    }

    @Test("添付だけで options と placement が供給される")
    func attachmentAloneSuppliesAttributes() {
        var options = Self.plainOptions()
        options.overlayColor = .clear
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        contentView.ksDialogOptions = options
        contentView.ksDialogPlacement = DialogPlacement(horizontalAlignment: .end)

        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.screen,
            insets: Self.insets
        )
        defer { stage.window.isHidden = true }

        // 水平は End (400 − 280)、垂直は window 基準の Center ((800 − 180) / 2)。
        DialogRectExpectation.expect(contentView.frame, equals: CGRect(x: 120, y: 310, width: 280, height: 180))
        #expect(stage.container.overlayView.backgroundColor == UIColor.clear, "添付した overlayColor が覆いに反映されること")
    }

    @Test("factory の添付と show の placement 引数が合成される")
    func factoryAttachmentAndShowPlacementAreComposed() async throws {
        let harness = DialogTestHarness()
        harness.registry.register(BasicTestDialogViewModel.self) { _, _ in
            let contentView = FixedContentSizeView(contentSize: Self.contentSize)
            var options = Self.plainOptions()
            options.overlayColor = .clear
            contentView.ksDialogOptions = options
            contentView.ksDialogPlacement = DialogPlacement(horizontalAlignment: .end, verticalAlignment: .end)
            return contentView
        }

        let showTask = Task {
            try await harness.dialogs.show(
                BasicTestDialogViewModel(message: "合成"),
                placement: DialogPlacement(horizontalAlignment: .start, verticalAlignment: .start)
            )
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        let frame = try #require(harness.presentationSurface.contentFramesAtPresentation.first)
        container.reportOutsideTap()
        _ = try? await showTask.value

        // 配置は show 引数の Start / Start、覆いは添付した options の透明。
        DialogRectExpectation.expect(frame, equals: CGRect(x: 0, y: 0, width: 280, height: 180))
        #expect(container.overlayView.backgroundColor == UIColor.clear)
    }

    @Test("show 引数の placement が添付の placement に勝つ")
    func showPlacementWinsOverAttachedPlacement() {
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        contentView.ksDialogOptions = Self.plainOptions()
        contentView.ksDialogPlacement = DialogPlacement(horizontalAlignment: .end)

        let actual = DialogLayoutMeasurement.measureContentFrame(
            contentView: contentView,
            showPlacement: DialogPlacement(horizontalAlignment: .start),
            screen: Self.screen,
            insets: Self.insets
        )

        // 水平は show 引数の Start。垂直の 310 は添付した options (window 基準) が
        // 引き続き効いていることを示す (visibleArea なら 320 になる)。
        DialogRectExpectation.expect(actual, equals: CGRect(x: 0, y: 310, width: 280, height: 180))
    }

    @Test("show 引数の placement は添付をオブジェクト単位で置換する")
    func showPlacementReplacesAttachedPlacementAsWhole() {
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        contentView.ksDialogOptions = Self.plainOptions()
        contentView.ksDialogPlacement = DialogPlacement(
            horizontalAlignment: .end,
            verticalAlignment: .end,
            offsetX: 30,
            offsetY: 40
        )

        let actual = DialogLayoutMeasurement.measureContentFrame(
            contentView: contentView,
            showPlacement: DialogPlacement(horizontalAlignment: .start),
            screen: Self.screen,
            insets: Self.insets
        )

        // 実効 placement は show 引数のオブジェクト全体 (水平 Start・垂直 Center・Offset 0)。
        // フィールド単位で合成していれば垂直 End と Offset が残り、(30, 660) になる。
        DialogRectExpectation.expect(actual, equals: CGRect(x: 0, y: 310, width: 280, height: 180))
    }

    @Test("初回レイアウト完了前の添付変更は採用される")
    func attachmentChangeBeforeFirstLayoutPassCompletesIsAdopted() {
        // 中身が自分のレイアウトの中で添付し直す = View の生成後・初回レイアウトパスの完了前の供給。
        let contentView = LateAttachingContentView(contentSize: Self.contentSize) { view in
            var options = Self.plainOptions()
            options.isCanceledOnTouchOutside = false
            view.ksDialogOptions = options
            view.ksDialogPlacement = DialogPlacement(
                horizontalAlignment: .end,
                verticalAlignment: .end
            )
        }
        contentView.ksDialogOptions = Self.plainOptions()
        contentView.ksDialogPlacement = DialogPlacement(horizontalAlignment: .start, verticalAlignment: .start)
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

        // 採用されるのはパス完了時点の値 = 遅れて届いた End / End。
        // 器の構築時に固定していれば Start / Start のまま (0, 0) になる。
        #expect(contentView.attachCount == 1, "供給はレイアウトパスの中で1度だけ起きること")
        DialogRectExpectation.expect(contentView.frame, equals: CGRect(x: 120, y: 620, width: 280, height: 180))

        stage.container.reportOutsideTap()

        #expect(recorder.count == 0, "操作挙動も完了前に届いた値 (false) に従う")
    }

    @Test("提示のあと画面上の初回レイアウトで届いた添付が採用される")
    func attachmentChangeDuringFirstOnScreenLayoutPassIsAdopted() async throws {
        let harness = DialogTestHarness()
        harness.registry.register(BasicTestDialogViewModel.self) { _, _ in
            // 供給が届くのは画面に載ったあとのレイアウトパスの中 = 提示より後。
            let contentView = LateAttachingContentView(contentSize: Self.contentSize) { view in
                var options = Self.plainOptions()
                options.isCanceledOnTouchOutside = false
                view.ksDialogOptions = options
                view.ksDialogPlacement = DialogPlacement(
                    horizontalAlignment: .end,
                    verticalAlignment: .end
                )
            }
            contentView.ksDialogOptions = Self.plainOptions()
            contentView.ksDialogPlacement = DialogPlacement(
                horizontalAlignment: .start,
                verticalAlignment: .start
            )
            return contentView
        }

        let showTask = Task {
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "遅れて届く添付"))
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        let contentView = try #require(container.contentView as? LateAttachingContentView)
        let frameAtPresentation = try #require(harness.presentationSurface.contentFramesAtPresentation.first)
        let bounds = harness.presentationSurface.presentationBounds

        // 提示より前の暫定のレイアウトでは、まだ添付は Start / Start のまま。
        DialogRectExpectation.expect(frameAtPresentation, equals: CGRect(x: 0, y: 0, width: 280, height: 180))
        // 画面に載せたあとの初回パスで届いた End / End が採用される。
        // 提示より前に固定していれば Start / Start のまま (0, 0) になる。
        #expect(contentView.attachCount == 1, "供給は画面上の初回レイアウトパスの中で1度だけ起きること")
        DialogRectExpectation.expect(
            contentView.frame,
            equals: CGRect(
                x: bounds.width - Self.contentSize.width,
                y: bounds.height - Self.contentSize.height,
                width: Self.contentSize.width,
                height: Self.contentSize.height
            )
        )

        // 操作挙動も届いた値 (false) に従うため、外側タップでは閉じない。
        container.reportOutsideTap()
        let closed = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) {
            harness.presentedContainers.isEmpty
        }
        #expect(closed == false, "外側タップの扱いも完了前に届いた値 (false) に従う")

        showTask.cancel()
        _ = try? await showTask.value
    }

    @Test("初回レイアウト完了後の添付変更は表示にも操作にも反映されない")
    func attachmentChangeAfterFirstLayoutPassIsIgnored() {
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        contentView.ksDialogOptions = Self.plainOptions()
        contentView.ksDialogPlacement = DialogPlacement(horizontalAlignment: .start, verticalAlignment: .start)
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
        let frameAtFirstLayoutPass = contentView.frame

        var changedOptions = Self.plainOptions()
        changedOptions.isCanceledOnTouchOutside = false
        contentView.ksDialogOptions = changedOptions
        contentView.ksDialogPlacement = DialogPlacement(
            horizontalAlignment: .end,
            verticalAlignment: .end,
            offsetX: 50
        )
        stage.container.view.setNeedsLayout()
        stage.container.view.layoutIfNeeded()

        DialogRectExpectation.expect(frameAtFirstLayoutPass, equals: CGRect(x: 0, y: 0, width: 280, height: 180))
        #expect(contentView.frame == frameAtFirstLayoutPass, "位置と見えはスナップショットのまま")

        stage.container.reportOutsideTap()

        #expect(recorder.count == 1, "外側タップの扱いもスナップショット時点の値 (既定 true) に従う")
        #expect(recorder.isFirstCancelled)
    }

    @Test("無効値は正規化された実効値として扱われる")
    func invalidValuesAreNormalized() {
        var options = DialogOptions(layoutArea: .window)
        options.proportionalWidth = .nan
        options.proportionalHeight = 1.5
        options.dialogMargin = DialogEdgeInsets(top: -10, left: .nan, bottom: 0, right: 0)
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        contentView.ksDialogOptions = options
        contentView.ksDialogPlacement = DialogPlacement(offsetX: .infinity)

        let actual = DialogLayoutMeasurement.measureContentFrame(
            contentView: contentView,
            screen: Self.screen,
            insets: Self.insets
        )

        // 比率は 幅 = 非有限で未指定 / 高さ = 1 へ丸め、余白は 上 = 負で 0 / 左 = 非有限で既定 24、
        // Offset は非有限で 0。水平は有効領域 (24〜400) の中央、垂直は基準 rect いっぱいになる。
        DialogRectExpectation.expect(actual, equals: CGRect(x: 72, y: 0, width: 280, height: 800))
    }
}
#endif
