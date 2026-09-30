#if canImport(UIKit)
import Foundation
import Testing

@testable import KsDialogs

@Suite("呼び出しコンテキストの契約", .serialized)
@MainActor
struct DialogCallContextTests {
    @Test("UI スレッド外からの show が成立する")
    func showFromNonUIThreadSucceeds() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            #expect(DialogTestThread.isMainThread(), "View の生成は UI スレッドで行われる")
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let dialogs = harness.dialogs
        let viewModel = BasicTestDialogViewModel(message: "こんにちは")
        let showTask = Task.detached { () -> (Bool, DialogResult<Bool>) in
            let calledOffMainThread = !DialogTestThread.isMainThread()
            let result = try await dialogs.show(viewModel)
            return (calledOffMainThread, result)
        }

        let notifier = try await recorder.notifier(at: 0)
        notifier.complete(true)

        let (calledOffMainThread, result) = try await showTask.value
        #expect(calledOffMainThread)
        #expect(result == .completed(true))
    }

    @Test("呼び出し元のキャンセルで cancelled が確定し器も残らない")
    func cancellingCallerSettlesCancelled() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "こんにちは")) }
        _ = try await recorder.notifier(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        showTask.cancel()

        #expect(try await showTask.value == .cancelled)
        #expect(await harness.waitForPresentedContainers(count: 0))
    }

    @Test("[PB-HW-01] 提示先が無い間は待ち、現れたら表示する")
    func PB_HW_01_waitsWhileNoHostAndPresentsWhenHostAppears() async throws {
        let harness = DialogTestHarness(hasPresentationHost: false)
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "こんにちは")) }
        try #require(
            await DialogTestWaiting.waitUntil { harness.presentationSurface.hostWaitQueue.waitingCount == 1 },
            "show は失敗も完了もせず、提示先を待つ列に並ぶ"
        )
        #expect(recorder.createdViews.isEmpty, "提示先が無い間は View factory が呼ばれない")
        #expect(harness.presentedContainers.isEmpty)

        harness.presentationSurface.isPresentationHostAvailable = true
        harness.presentationSurface.fireHostAppearance()

        let notifier = try await recorder.notifier(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1), "提示先が現れた時点で表示される")
        #expect(recorder.createdViews.count == 1)
        notifier.complete(true)

        #expect(try await showTask.value == .completed(true))
        #expect(harness.presentationSurface.hostAppearance.activeRegistrationCount == 0, "表示したら購読を解除する")
    }
}
#endif
