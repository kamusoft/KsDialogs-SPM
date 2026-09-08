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

    @Test("提示 host 不在の show は即失敗する")
    func showWithoutPresentationHostFails() async throws {
        let harness = DialogTestHarness(hasPresentationHost: false)
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        await #expect(throws: DialogError.presentationHostUnavailable) {
            _ = try await harness.dialogs.show(BasicTestDialogViewModel(message: "こんにちは"))
        }
        #expect(recorder.createdViews.isEmpty)
        #expect(harness.presentedContainers.isEmpty)
    }
}
#endif
