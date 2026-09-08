#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 多段表示の系列を、器を実際にウィンドウへ載せた状態で観察する。
///
/// 契約ロジックだけを見る `DialogMultiDisplayTests` との違いは、器の段階と出入りの演出まで
/// 観察対象に含めることにある。iOS では提示の連なりから外れた器は OS 発の消失として扱われ、
/// 退出の演出を伴わずに結果が確定する (core/ADR-0017)。
@Suite("多段表示の系列挙動", .serialized)
@MainActor
struct DialogMultiDisplayPresentationTests {
    @Test("[PB-MD-04] 下の段を先に閉じると上の段は演出なしで cancelled になる")
    func PB_MD_04_closingBottomSettlesTopAsCancelledWithoutHooks() async throws {
        let series = try await presentTwoDialogs()

        let bottomContainer = try #require(series.harness.presentedContainers.first)
        let topContainer = try #require(series.harness.topmostContainer)
        try #require(await waitUntil { topContainer.containerState == .shown })
        // 両段とも演出の添付が器に届いていることを、退出の観察より先に確かめる。
        try #require(series.bottomProbe.callCount(.presentation) == 1)
        try #require(series.topProbe.callCount(.presentation) == 1)

        // 下の段の結果報告口へ先に報告する (アプリコードが下の口を保持している場合にだけ起きる状況)。
        try await series.recorder.notifier(at: 0).complete(false)

        #expect(try await series.bottomTask.value == .completed(false))
        // iOS は提示の連なりごと外れるため、上の段も画面から消えて cancelled で確定する。
        #expect(try await series.topTask.value == .cancelled)
        #expect(await series.harness.waitForPresentedContainers(count: 0))

        // 下の段はライブラリ発の閉鎖なので退出の演出を通る。
        #expect(series.bottomProbe.callCount(.dismissal) == 1)
        // 上の段は OS 発の消失なので退出の演出を通らない。
        #expect(series.topProbe.callCount(.dismissal) == 0)
        #expect(bottomContainer.containerState == .removed)
        #expect(topContainer.containerState == .removed)
        #expect(topContainer.view.window == nil, "上の段もウィンドウから外れる")
    }

    @Test("[PB-MD-05] 重ね出し中に器が画面から外れると各 show が cancelled で1回だけ確定する")
    func PB_MD_05_hostLossSettlesEveryShowAsCancelledOnce() async throws {
        let series = try await presentTwoDialogs()

        let bottomContainer = try #require(series.harness.presentedContainers.first)
        let topContainer = try #require(series.harness.topmostContainer)
        try #require(await waitUntil { topContainer.containerState == .shown })
        try #require(series.bottomProbe.callCount(.presentation) == 1)
        try #require(series.topProbe.callCount(.presentation) == 1)

        // 報告を経ずに画面ごと破棄される (提示の連なりが根元から外れる) 状況を作る。
        series.harness.presentationSurface.simulateHostLoss(of: bottomContainer)

        #expect(try await series.bottomTask.value == .cancelled)
        #expect(try await series.topTask.value == .cancelled)
        #expect(await series.harness.waitForPresentedContainers(count: 0))

        // 器消失は演出を伴わない。
        #expect(series.bottomProbe.callCount(.dismissal) == 0)
        #expect(series.topProbe.callCount(.dismissal) == 0)
        #expect(bottomContainer.containerState == .removed)
        #expect(topContainer.containerState == .removed)

        // 確定後に報告しても結果は増えない (ちょうど1回)。
        try await series.recorder.notifier(at: 0).complete(true)
        try await series.recorder.notifier(at: 1).complete(true)
        #expect(series.recorder.results.count == 2)
        #expect(series.recorder.results.allSatisfy { $0 == .cancelled })
    }

    // MARK: 組み立て

    /// 2枚重ねた1回分の系列と、その観測に必要な道具。
    private struct Series {
        let harness: DialogTestHarness
        let recorder: DialogTestRecorder<Bool>
        let bottomProbe: DialogTransitionProbe
        let topProbe: DialogTransitionProbe
        let bottomTask: Task<DialogResult<Bool>, any Error>
        let topTask: Task<DialogResult<Bool>, any Error>
    }

    /// ダイアログを2枚重ねて表示し、器がウィンドウに載るまで待つ。
    /// 段ごとに別の観測用の道具を添付し、どちらの段の演出が動いたかを取り違えないようにする。
    private func presentTwoDialogs() async throws -> Series {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        let bottomProbe = DialogTransitionProbe()
        let topProbe = DialogTransitionProbe()

        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            // 1枚目が下の段、2枚目が上の段になる。
            let probe = recorder.notifiers.isEmpty ? bottomProbe : topProbe
            view.ksDialogTransition = DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.immediateHook(.dismissal)
            )
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

        return Series(
            harness: harness,
            recorder: recorder,
            bottomProbe: bottomProbe,
            topProbe: topProbe,
            bottomTask: bottomTask,
            topTask: topTask
        )
    }

    /// 条件が満たされるまで待つ。
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        await DialogTestWaiting.waitUntil(condition)
    }
}
#endif
