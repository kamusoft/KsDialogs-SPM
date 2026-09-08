#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

@Suite("SwiftUI 添付 DSL", .serialized)
@MainActor
struct DialogSwiftUIAttributeDslTests {
    /// 400 × 800 のウィンドウ。期待値は軸別レイアウト規則から導いてある。
    private static let screen = DialogLayoutCase.Size(w: 400, h: 800)
    private static let insets = DialogLayoutCase.Insets(top: 50, bottom: 30, left: 0, right: 0)
    private static let contentSize = CGSize(width: 280, height: 180)

    /// ウィンドウ全体を基準にし余白を持たない静的メタ属性。
    /// 期待値の導出を単純にするため、供給経路そのものを見たいテストではこれを土台にする。
    private static func plainOptions() -> DialogOptions {
        DialogOptions(layoutArea: .window, dialogMargin: .zero)
    }

    @Test(
        "添付 DSL で供給した実効値が共通ケース表に適合する",
        arguments: DialogLayoutCaseLoader.table.cases
    )
    func attachedAttributesMatchSharedCaseTable(layoutCase: DialogLayoutCase) async throws {
        // ケース表の attributes は供給を合成した後の実効値なので、添付だけで与えれば足りる。
        let content = FixedSizeSwiftUIContent(
            contentSize: CGSize(width: layoutCase.contentSize.w, height: layoutCase.contentSize.h)
        )
        .ksDialogOptions(layoutCase.attributes.options)
        .ksDialogPlacement(layoutCase.attributes.placement)

        let actual = try await DialogSwiftUIMeasurement.measureContentFrame(
            content: content,
            screen: layoutCase.screen,
            insets: layoutCase.insets
        )

        let expected = layoutCase.expected
        DialogRectExpectation.expect(
            actual,
            equals: CGRect(x: expected.x, y: expected.y, width: expected.w, height: expected.h),
            layoutCase.id
        )
    }

    @Test("非レイアウト属性も添付 DSL で届く")
    func nonLayoutAttributesAreSuppliedByAttachment() async throws {
        var options = Self.plainOptions()
        options.overlayColor = .clear
        options.isCanceledOnTouchOutside = false
        let content = FixedSizeSwiftUIContent(contentSize: Self.contentSize)
            .ksDialogOptions(options)
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }

        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: content,
            screen: Self.screen,
            insets: Self.insets,
            resultChannel: resultChannel
        )
        defer { stage.window.isHidden = true }

        #expect(stage.container.overlayView.backgroundColor == UIColor.clear, "添付した overlayColor が覆いに反映されること")

        stage.container.reportOutsideTap()

        #expect(recorder.count == 0, "添付した isCanceledOnTouchOutside = false により外側タップで閉じないこと")
    }

    @Test("添付なしは従来 View 系と同じ契約既定値で、到達待ちも起きない")
    func contentWithoutAttachmentUsesContractDefaults() async throws {
        let expectedStage = DialogLayoutMeasurement.layoutInWindow(
            contentView: FixedContentSizeView(contentSize: Self.contentSize),
            screen: Self.screen,
            insets: Self.insets
        )
        defer { expectedStage.window.isHidden = true }
        let expected = expectedStage.container.contentView.frame

        let stage = DialogLayoutMeasurement.layoutInWindow(
            content: DialogSwiftUIHost.makeContent(FixedSizeSwiftUIContent(contentSize: Self.contentSize)),
            screen: Self.screen,
            insets: Self.insets
        )
        defer { stage.window.isHidden = true }

        // 添付なしでも供給は同期に解決するため、追加のレイアウトパスを待たずに固定される。
        #expect(stage.container.isLayoutSnapshotFrozen, "到達待ちによる提示の繰り下げが起きないこと")
        #expect(stage.container.didExhaustAttributeSupplyWait == false)
        DialogRectExpectation.expect(stage.container.contentView.frame, equals: expected)
    }

    @Test("到達上限を過ぎた供給は契約既定値になり、提示は止まらない")
    func attributeSupplyBeyondWaitLimitFallsBackToDefaults() async throws {
        let expectedStage = DialogLayoutMeasurement.layoutInWindow(
            contentView: FixedContentSizeView(contentSize: Self.contentSize),
            screen: Self.screen,
            insets: Self.insets
        )
        defer { expectedStage.window.isHidden = true }
        let expected = expectedStage.container.contentView.frame

        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: NeverResolvingAttributeSupplyView(contentSize: Self.contentSize),
            screen: Self.screen,
            insets: Self.insets
        )
        defer { stage.window.isHidden = true }

        // 供給が届かないので追加のレイアウトパスを1回だけ待ち、そのあと契約既定値で固定する。
        #expect(stage.container.isLayoutSnapshotFrozen == false, "上限に達するまでは固定を繰り下げること")
        let frozen = await DialogTestWaiting.waitUntil { stage.container.isLayoutSnapshotFrozen }
        #expect(frozen, "上限に達したら固定して提示を進めること")
        #expect(stage.container.didExhaustAttributeSupplyWait, "到達しなかったことが記録されること")
        stage.window.layoutIfNeeded()
        DialogRectExpectation.expect(stage.container.contentView.frame, equals: expected)
    }

    @Test("同一属性の重畳は外側の添付が勝つ")
    func outermostAttachmentWinsForSameAttribute() async throws {
        let content = FixedSizeSwiftUIContent(contentSize: Self.contentSize)
            .ksDialogPlacement(DialogPlacement(horizontalAlignment: .start, verticalAlignment: .start))
            .ksDialogPlacement(DialogPlacement(horizontalAlignment: .end, verticalAlignment: .end))
            .ksDialogOptions(Self.plainOptions())

        let actual = try await DialogSwiftUIMeasurement.measureContentFrame(
            content: content,
            screen: Self.screen,
            insets: Self.insets
        )

        // 外側の End / End が採用される。内側が勝てば (0, 0) になる。
        DialogRectExpectation.expect(
            actual,
            equals: CGRect(
                x: Self.screen.w - Self.contentSize.width,
                y: Self.screen.h - Self.contentSize.height,
                width: Self.contentSize.width,
                height: Self.contentSize.height
            )
        )
    }

    @Test("提示後に添付値が変わっても表示にも操作にも反映されない")
    func attachmentChangeAfterPresentationIsIgnored() async throws {
        var changedOptions = Self.plainOptions()
        changedOptions.overlayColor = .clear
        changedOptions.isCanceledOnTouchOutside = false
        let attributeSwitch = TogglingAttributeSwiftUIContent.Switch()
        let content = TogglingAttributeSwiftUIContent(
            contentSize: Self.contentSize,
            attributeSwitch: attributeSwitch,
            initialOptions: Self.plainOptions(),
            initialPlacement: DialogPlacement(horizontalAlignment: .start, verticalAlignment: .start),
            changedOptions: changedOptions,
            changedPlacement: DialogPlacement(horizontalAlignment: .end, verticalAlignment: .end)
        )
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }

        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: content,
            screen: Self.screen,
            insets: Self.insets,
            resultChannel: resultChannel
        )
        defer { stage.window.isHidden = true }
        let frameAtSnapshot = stage.container.contentView.frame
        let overlayColorAtSnapshot = stage.container.overlayView.backgroundColor

        attributeSwitch.usesChangedAttributes = true
        // 供給そのものは中身から届き続けている (器が採らないだけである) ことを先に確かめる。
        let supplied = await DialogTestWaiting.waitUntil {
            stage.window.layoutIfNeeded()
            return stage.container.contentView.ksDialogOptions?.isCanceledOnTouchOutside == false
        }
        #expect(supplied, "変更後の添付値が中身から届いていること")

        DialogRectExpectation.expect(stage.container.contentView.frame, equals: frameAtSnapshot, "位置はスナップショットのまま")
        #expect(stage.container.overlayView.backgroundColor == overlayColorAtSnapshot, "覆いの色もスナップショットのまま")

        stage.container.reportOutsideTap()

        #expect(recorder.count == 1, "外側タップの扱いもスナップショット時点の値 (既定 true) に従う")
        #expect(recorder.isFirstCancelled)
    }
}
#endif
