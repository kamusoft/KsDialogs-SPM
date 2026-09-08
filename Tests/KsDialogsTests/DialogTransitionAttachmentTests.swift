#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

@Suite("トランジション添付面", .serialized)
@MainActor
struct DialogTransitionAttachmentTests {
    @Test("[PB-IA-01] UIView への添付が器で採用される")
    func PB_IA_01_uiViewAttachmentIsAdopted() async throws {
        let probe = DialogTransitionProbe()
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            view.ksDialogTransition = DialogTransition(presentation: probe.immediateHook(.presentation))
            recorder.record(view: view, notifier: notifier)
            return view
        }
        let task = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 })

        let call = try #require(probe.firstCall(.presentation))
        #expect(call.hostView === recorder.createdViews.first, "そのコンテンツのホスト View が渡る")
        #expect(call.isOnMainThread)

        try await recorder.notifier(at: 0).complete(true)
        #expect(try await task.value == .completed(true))
    }

    @Test("[PB-IA-02] SwiftUI modifier での添付が器で採用される")
    func PB_IA_02_swiftUIModifierAttachmentIsAdopted() async throws {
        let probe = DialogTransitionProbe()
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            recorder.recording(
                notifier: notifier,
                content: FixedSizeSwiftUIContent(contentSize: CGSize(width: 240, height: 120))
                    .ksDialogTransition(DialogTransition(presentation: probe.immediateHook(.presentation)))
            )
        }
        let task = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 })

        let call = try #require(probe.firstCall(.presentation))
        let container = try #require(harness.topmostContainer)
        #expect(call.hostView === container.contentView, "SwiftUI の中身を包むホスト View が渡る")
        #expect(call.hostView is DialogSwiftUIContentView)
        #expect(call.isOnMainThread)

        try await recorder.notifier(at: 0).complete(true)
        #expect(try await task.value == .completed(true))
    }
}
#endif
