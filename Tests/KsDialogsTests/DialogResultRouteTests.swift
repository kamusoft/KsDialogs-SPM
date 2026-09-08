#if canImport(UIKit)
import Testing

@testable import KsDialogs

@Suite("型付き結果の show", .serialized)
@MainActor
struct DialogResultRouteTests {
    @Test("完了操作で completed が返る")
    func completedResultIsReturned() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "こんにちは")) }
        let notifier = try await recorder.notifier(at: 0)
        notifier.complete(true)

        #expect(try await showTask.value == .completed(true))
    }

    @Test("キャンセル操作で cancelled が返る")
    func cancelledResultIsReturned() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "こんにちは")) }
        let notifier = try await recorder.notifier(at: 0)
        notifier.cancel()

        #expect(try await showTask.value == .cancelled)
    }

    @Test("外側タップで cancelled が返る (既定)")
    func outsideTapReturnsCancelled() async throws {
        let harness = DialogTestHarness()
        harness.registry.register(BasicTestDialogViewModel.self) { _, _ in DialogTestContentView() }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "こんにちは")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        harness.topmostContainer?.reportOutsideTap()

        #expect(try await showTask.value == .cancelled)
    }

    @Test("Swift から show して結果を受け取る")
    func typedResultIsReturnedToSwiftCaller() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { viewModel, notifier in
            let view = DialogTestContentView()
            #expect(viewModel.message == "こんにちは、KsDialogs!")
            recorder.record(view: view, notifier: notifier)
            return view
        }

        // 受け取り型を明示することで、結果型が ViewModel の宣言から導出されることを型検査で確かめる。
        let showTask = Task { () -> DialogResult<Bool> in
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "こんにちは、KsDialogs!"))
        }
        let notifier = try await recorder.notifier(at: 0)
        notifier.complete(true)

        let result: DialogResult<Bool> = try await showTask.value
        guard case .completed(let value) = result else {
            Issue.record("completed で完了しなかった: \(result)")
            return
        }
        #expect(value == true)
    }
}
#endif
