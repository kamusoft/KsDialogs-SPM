#if canImport(UIKit)
import Testing

@testable import KsDialogs

@Suite("多段表示の基本保証", .serialized)
@MainActor
struct DialogMultiDisplayTests {
    /// ダイアログを2枚重ねて表示し、下から順の結果報告口と各 show の結果記録を返す。
    private func presentTwoDialogs(
        harness: DialogTestHarness,
        recorder: DialogTestRecorder<Bool>
    ) async throws -> (bottom: Task<DialogResult<Bool>, any Error>, top: Task<DialogResult<Bool>, any Error>) {
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let bottomTask = Task { () -> DialogResult<Bool> in
            let result = try await harness.dialogs.show(BasicTestDialogViewModel(message: "下"))
            recorder.record(result: result)
            return result
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let topTask = Task { () -> DialogResult<Bool> in
            let result = try await harness.dialogs.show(BasicTestDialogViewModel(message: "上"))
            recorder.record(result: result)
            return result
        }
        try #require(await harness.waitForPresentedContainers(count: 2))
        return (bottomTask, topTask)
    }

    @Test("[PB-MD-01] 結果確定で自分のダイアログだけが閉じる")
    func PB_MD_01_settlementClosesOnlyOwnDialog() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        let (bottomTask, topTask) = try await presentTwoDialogs(harness: harness, recorder: recorder)

        recorder.notifiers[1].complete(true)
        #expect(try await topTask.value == .completed(true))

        try #require(await harness.waitForPresentedContainers(count: 1))
        #expect(recorder.results.count == 1)

        recorder.notifiers[0].complete(false)
        #expect(try await bottomTask.value == .completed(false))
    }

    @Test("[PB-MD-02] 2枚重ねて上から順に閉じる")
    func PB_MD_02_closeFromTop() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        let (bottomTask, topTask) = try await presentTwoDialogs(harness: harness, recorder: recorder)

        // 2枚を異なる結果値で閉じ、結果チャネルの取り違えがないことまで観察する。
        recorder.notifiers[1].complete(true)
        #expect(try await topTask.value == .completed(true))

        try #require(await harness.waitForPresentedContainers(count: 1))
        recorder.notifiers[0].complete(false)
        #expect(try await bottomTask.value == .completed(false))

        #expect(await harness.waitForPresentedContainers(count: 0))
    }

    @Test("[PB-MD-03] 重ね出し中の外側タップは手前のみに届く")
    func PB_MD_03_outsideTapClosesTopOnly() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        let (bottomTask, topTask) = try await presentTwoDialogs(harness: harness, recorder: recorder)

        let topContainer = try #require(harness.topmostContainer)
        topContainer.reportOutsideTap()
        #expect(try await topTask.value == .cancelled)

        // 下の1枚は表示されたまま結果未確定であることを、待ち合わせずに観察する。
        try #require(await harness.waitForPresentedContainers(count: 1))
        #expect(recorder.results.count == 1)

        recorder.notifiers[0].complete(false)
        #expect(try await bottomTask.value == .completed(false))
    }

    @Test("[PB-MD-04] 下の段を先に閉じたときの挙動")
    func PB_MD_04_closeFromBottom() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        let (bottomTask, topTask) = try await presentTwoDialogs(harness: harness, recorder: recorder)

        // 下 (先に出した) の結果報告口へ先に完了報告する。
        recorder.notifiers[0].complete(false)

        // 保証されるのは「各 show が自分の結果値で独立に確定すること」だけ。
        #expect(try await bottomTask.value == .completed(false))

        // どちらの器が画面から消えるかは保証範囲外だが、器が画面から外れた show は
        // 結果が確定しないまま宙吊りにならない。
        #expect(try await topTask.value == .cancelled)
        #expect(await harness.waitForPresentedContainers(count: 0))
    }
}
#endif
