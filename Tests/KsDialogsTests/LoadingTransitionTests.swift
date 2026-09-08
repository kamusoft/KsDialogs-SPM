#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Loading の出入りの演出 (core/ADR-0017・0022) を確かめる。
///
/// カスタム Loading View は Dialog と同じ添付スロットで演出を差し替えられ、
/// 未添付のカスタム View と既定ローディングはライブラリ既定の演出で出入りする。
/// 覆いはフックの内容によらず、中身とは別のレイヤでフェードする。
@Suite("Loading の出入りの演出", .serialized)
@MainActor
struct LoadingTransitionTests {
    private static let contentSize = CGSize(width: 120, height: 80)

    @Test("[LD-TR-01] カスタム View の添付演出フックが実行される")
    func LD_TR_01_attachedHooksRunOnPresentationAndDismissal() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let probe = DialogTransitionProbe()
        let dismissalGate = DialogTransitionGate()
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            view.ksDialogTransition = DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.gatedHook(.dismissal, gate: dismissalGate)
            )
            viewRecorder.record(view)
            return view
        }

        try await harness.loading.show(LoadingTestViewModel())
        let contentView = try #require(harness.contentView)

        try #require(await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 })
        let presentationCall = try #require(probe.firstCall(.presentation))
        #expect(presentationCall.hostView === contentView, "フックはホスト View を受け取る")
        #expect(presentationCall.isOnWindow, "フックが始まる時点でホスト View は画面に載っている")
        #expect(probe.callCount(.dismissal) == 0)

        let hiding = Task { await harness.loading.hide() }
        try #require(await DialogTestWaiting.waitUntil { probe.callCount(.dismissal) == 1 })
        let dismissalCall = try #require(probe.firstCall(.dismissal))
        #expect(dismissalCall.hostView === contentView)
        #expect(contentView.window != nil, "出のフックの完了前は撤去されない")

        dismissalGate.open()
        await hiding.value
        #expect(contentView.window == nil, "出のフックの完了後に撤去される")
        #expect(harness.isPresenting == false)
    }

    @Test("[LD-TR-02] 未添付なら既定のトランジションで出入りする")
    func LD_TR_02_defaultTransitionIsUsedWithoutAttachment() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let probe = DialogTransitionProbe()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }

        // 演出を添付しないカスタム View。
        try await harness.loading.show(LoadingTestViewModel())
        let customContainer = try #require(harness.coordinator.presentedContainer)
        try #require(await DialogTestWaiting.waitUntil { customContainer.resolvedTransition != nil })
        let customTransition = try #require(customContainer.resolvedTransition)
        #expect(customTransition.presentation != nil, "未添付側は器の既定で埋まる")
        #expect(customTransition.dismissal != nil)
        let customContentView = try #require(harness.contentView)
        try #require(await DialogTestWaiting.waitUntil { customContentView.alpha == 1 })
        await harness.loading.hide()

        // 既定ローディング。
        await harness.loading.show()
        let builtinContainer = try #require(harness.coordinator.presentedContainer)
        try #require(await DialogTestWaiting.waitUntil { builtinContainer.resolvedTransition != nil })
        let builtinTransition = try #require(builtinContainer.resolvedTransition)
        #expect(builtinTransition.presentation != nil)
        #expect(builtinTransition.dismissal != nil)
        let builtinContentView = try #require(harness.contentView)
        try #require(await DialogTestWaiting.waitUntil { builtinContentView.alpha == 1 })
        await harness.loading.hide()

        #expect(probe.events.isEmpty, "フックを添付していないので利用者のフックは走らない")
    }

    @Test("[LD-TR-03] 覆いは別レイヤでフェードする")
    func LD_TR_03_overlayFadesOnItsOwnLayer() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let probe = DialogTransitionProbe()
        let presentationGate = DialogTransitionGate()
        let dismissalGate = DialogTransitionGate()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            view.ksDialogTransition = DialogTransition(
                presentation: probe.gatedHook(.presentation, gate: presentationGate),
                dismissal: probe.gatedHook(.dismissal, gate: dismissalGate)
            )
            return view
        }

        try await harness.loading.show(LoadingTestViewModel())
        let container = try #require(harness.coordinator.presentedContainer)
        let contentView = try #require(harness.contentView)
        let overlayView = container.overlayView

        // 入りのフックが終わらないうちに覆いは現れる (フックの内容に依存しない)。
        try #require(await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 })
        try #require(await DialogTestWaiting.waitUntil { overlayView.alpha == 1 })
        #expect(probe.hasEvent(.finished(.presentation)) == false, "入りのフックはまだ完了していない")
        #expect(overlayView !== contentView, "覆いは中身とは別のレイヤ")
        #expect(overlayView.superview === container.view)
        presentationGate.open()

        let hiding = Task { await harness.loading.hide() }
        try #require(await DialogTestWaiting.waitUntil { probe.callCount(.dismissal) == 1 })
        try #require(await DialogTestWaiting.waitUntil { overlayView.alpha == 0 })
        #expect(probe.hasEvent(.finished(.dismissal)) == false, "出のフックはまだ完了していない")

        dismissalGate.open()
        await hiding.value
        #expect(harness.isPresenting == false)
    }
}
#endif
