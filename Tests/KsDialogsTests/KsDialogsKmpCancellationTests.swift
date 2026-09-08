#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("KMP 向け Swift 型付き公開面のキャンセル", .serialized)
@MainActor
struct KsDialogsKmpCancellationTests {
    /// 結果報告口を記録する factory を、真偽値の結果型で登録する。
    private func register(harness: DialogTestHarness, recorder: DialogTestRecorder<Bool>) {
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }
    }

    @Test("呼び出し元 Task のキャンセルでダイアログが閉じ cancelled が返る")
    func callerCancellationClosesDialog() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        register(harness: harness, recorder: recorder)

        let showTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "確認")) }
        try #require(await harness.waitForPresentedContainers(count: 1))

        showTask.cancel()

        #expect(try await showTask.value == .cancelled)
        #expect(await harness.waitForPresentedContainers(count: 0), "取り消しで表示が残らないこと")
    }

    @Test("キャンセル後の結果報告は無効で、結果は1回だけ確定する")
    func cancellationSettlesResultExactlyOnce() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        register(harness: harness, recorder: recorder)

        let showTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "確認")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let notifier = try await recorder.notifier(at: 0)

        showTask.cancel()
        #expect(try await showTask.value == .cancelled)

        // 確定後の報告は何も起こさない (結果はちょうど1回だけ有効)。
        notifier.complete(true)
        notifier.cancel()
        _ = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) {
            !harness.presentedContainers.isEmpty
        }

        #expect(harness.presentedContainers.isEmpty)
    }

    @Test("キャンセルは当該ダイアログだけを閉じ、他の表示中ダイアログは残る")
    func cancellationClosesOnlyItsOwnDialog() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        register(harness: harness, recorder: recorder)

        let keptTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "残す")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let keptContainer = try #require(harness.topmostContainer)
        let cancelledTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "取り消す")) }
        try #require(await harness.waitForPresentedContainers(count: 2))

        cancelledTask.cancel()

        #expect(try await cancelledTask.value == .cancelled)
        try #require(await harness.waitForPresentedContainers(count: 1))
        #expect(harness.topmostContainer === keptContainer, "取り消していないダイアログが残ること")

        try await recorder.notifier(at: 0).complete(true)
        #expect(try await keptTask.value == .completed(true))
    }

    @Test("提示が始まる前のキャンセルでも表示が残らない")
    func cancellationBeforePresentationLeavesNothing() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        register(harness: harness, recorder: recorder)

        let showTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "確認")) }
        showTask.cancel()

        #expect(try await showTask.value == .cancelled)
        #expect(await harness.waitForPresentedContainers(count: 0))
    }
}
#endif
