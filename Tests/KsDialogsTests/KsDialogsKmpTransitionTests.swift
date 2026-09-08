#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// KMP の登録面で登録した中身でも、Native 側で添付した出入りの演出が器に採用されることの検証。
///
/// 共有コードからの show は ObjC 互換面を通るため、型付きの KMP 面と互換面の両方で同じ添付を見る。
@Suite("KMP 登録コンテンツへのトランジション添付", .serialized)
@MainActor
struct KsDialogsKmpTransitionTests {
    @Test("[PB-KC-03] KMP 登録コンテンツへの添付が型付き面の show で採用される")
    func PB_KC_03_kmpTypedShowAdoptsAttachment() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        register(harness: harness, recorder: recorder, probe: probe, gate: gate)

        let showTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "確認")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 })

        let call = try #require(probe.firstCall(.presentation))
        #expect(call.hostView === recorder.createdViews.first, "KMP 登録の中身のホスト View が渡る")
        #expect(call.isOnMainThread)

        try await recorder.notifier(at: 0).complete(true)
        try #require(await DialogTestWaiting.waitUntil { probe.hasEvent(.started(.dismissal)) })
        #expect(harness.presentedContainers.count == 1, "dismissal フックの完了前は器が残っている")

        gate.open()
        #expect(try await showTask.value == .completed(true))
        #expect(harness.presentedContainers.isEmpty, "配送の時点で器は撤去済み")
    }

    @Test("[PB-KC-03] KMP 登録コンテンツへの添付が共有コードからの show で採用される")
    func PB_KC_03_sharedCodeShowAdoptsAttachment() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        register(harness: harness, recorder: recorder, probe: probe, gate: gate)
        let interopRecorder = DialogInteropTestRecorder()

        sharedCodeFace(harness: harness).show(SharedTestDialogViewModel(message: "確認")) { result in
            interopRecorder.record(result: result)
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 })

        let call = try #require(probe.firstCall(.presentation))
        #expect(call.hostView === recorder.createdViews.first, "KMP 登録の中身のホスト View が渡る")

        try await recorder.notifier(at: 0).complete(true)
        try #require(await DialogTestWaiting.waitUntil { probe.hasEvent(.started(.dismissal)) })
        #expect(interopRecorder.resultCount == 0, "dismissal フックの完了前は結果が届かない")

        gate.open()
        try #require(await DialogTestWaiting.waitUntil { interopRecorder.resultCount == 1 })
        #expect(try #require(interopRecorder.firstResult).kind == .completed)
        #expect(harness.presentedContainers.isEmpty, "配送の時点で器は撤去済み")
    }

    /// 共有 VM の型に、出入りの演出を添付した中身の factory を KMP の登録面で登録する。
    /// 閉鎖側は門で止めるので、結果の配送がフックの完了を待つかどうかを観察できる。
    private func register(
        harness: DialogTestHarness,
        recorder: DialogTestRecorder<Bool>,
        probe: DialogTransitionProbe,
        gate: DialogTransitionGate
    ) {
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            view.ksDialogTransition = DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.gatedHook(.dismissal, gate: gate)
            )
            recorder.record(view: view, notifier: notifier)
            return view
        }
    }

    /// 共有コードからの show に対応する経路。委譲面は同じレジストリと提示面を使う。
    private func sharedCodeFace(harness: DialogTestHarness) -> KsDialogsInteropBridge {
        KsDialogsInteropBridge(
            registry: harness.registry,
            presentationSurface: harness.presentationSurface
        )
    }
}
#endif
