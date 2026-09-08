#if canImport(UIKit)
import Foundation
import Testing
import UIKit

@testable import KsDialogs

@Suite("出入りの演出", .serialized)
@MainActor
struct DialogTransitionTests {
    /// 器を直接組み立てて観察するときの window の大きさ。
    private static let probeScreen = DialogLayoutCase.Size(w: 400, h: 800)
    /// 器を直接組み立てて観察するときのシステム領域の余白。
    private static let probeInsets = DialogLayoutCase.Insets(top: 50, bottom: 30, left: 0, right: 0)

    // MARK: 添付

    @Test("[PB-TR-01] presentation フックが表示時にちょうど1回、ホスト View を引数に UI スレッドで呼ばれる")
    func PB_TR_01_presentationHookRunsOnceWithHostView() async throws {
        let probe = DialogTransitionProbe()
        let stage = try await start(transition: DialogTransition(presentation: probe.immediateHook(.presentation)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))

        #expect(probe.callCount(.presentation) == 1)
        let call = try #require(probe.firstCall(.presentation))
        #expect(call.hostView === stage.harness.presentedContainers.first?.contentView)
        #expect(call.isOnMainThread)
        #expect(call.isOnWindow, "フックが始まる時点でホスト View はウィンドウ上にある")
        #expect(call.size != .zero, "フックが始まる時点でレイアウトは済んでいる")

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
    }

    @Test("[PB-TR-02] 片側だけの添付では未指定側に既定が適用される")
    func PB_TR_02_unspecifiedHookFallsBackToDefault() async throws {
        let probe = DialogTransitionProbe()
        let stage = try await start(transition: DialogTransition(dismissal: probe.immediateHook(.dismissal)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        #expect(probe.callCount(.presentation) == 0, "未指定側の presentation フックは呼ばれない")

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
        #expect(probe.callCount(.dismissal) == 1)
    }

    @Test("[PB-TR-03] 添付なしでは両フックとも呼ばれず既定のトランジションで表示・閉鎖される")
    func PB_TR_03_noAttachmentUsesDefaultTransition() async throws {
        let probe = DialogTransitionProbe()
        let stage = try await start(transition: nil)

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
        #expect(probe.events.isEmpty)
    }

    @Test("[PB-TR-04] 表示後の添付変更は退出に影響しない")
    func PB_TR_04_attachmentChangeAfterShowIsIgnored() async throws {
        let adopted = DialogTransitionProbe()
        let replaced = DialogTransitionProbe()
        let stage = try await start(transition: DialogTransition(dismissal: adopted.immediateHook(.dismissal)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        container.contentView.ksDialogTransition = DialogTransition(dismissal: replaced.immediateHook(.dismissal))

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
        #expect(adopted.callCount(.dismissal) == 1, "固定済みの演出が使われる")
        #expect(replaced.callCount(.dismissal) == 0, "書き換え後の演出は使われない")
    }

    /// 中身が見えるようになる瞬間と presentation フックの開始は、間に描画を挟まない。
    ///
    /// 見せてからフックが効くまでに1回でも描画の機会があると、滑り込みの演出でも
    /// 最終位置のカードが1フレーム映る。器を直接組み立て、器が進行を始めたのと同じ同期区間で
    /// 目印を立てる仕事を積むことで、その仕事より前にフックが最初の処理を終えていることを見る。
    @Test("中身の表示と presentation フックの開始の間に描画の機会がない")
    func contentBecomesVisibleInTheSameTurnAsThePresentationHook() async throws {
        let contentView = FixedContentSizeView(contentSize: CGSize(width: 200, height: 120))
        let gate = DialogTransitionGate()
        var didRunLaterWork = false
        var laterWorkSeenByHook: Bool?
        var alphaSeenByHook: CGFloat?
        contentView.ksDialogTransition = DialogTransition(
            presentation: { hostView in
                // フックに入って最初の同期処理。ここまでが「見せる」と同じ区間に入っている。
                laterWorkSeenByHook = didRunLaterWork
                alphaSeenByHook = hostView.alpha
                try await gate.wait()
            }
        )

        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.probeScreen,
            insets: Self.probeInsets
        )
        defer { stage.window.isHidden = true }
        // 器が進行を始めたのと同じ同期区間。この時点ではまだ中身を見せていない。
        #expect(contentView.alpha == 0, "フックが効く前の中身は描かれない")
        Task { @MainActor in didRunLaterWork = true }

        try #require(await waitUntil { alphaSeenByHook != nil })
        #expect(laterWorkSeenByHook == false, "見せてからフックが始まるまでに割り込む余地がない")
        #expect(alphaSeenByHook == 1, "フックが始まる時点で中身は見える状態になっている")
        gate.open()
    }

    // MARK: 退出の開始条件と直列化

    @Test("[PB-TR-05] presentation 中の閉鎖信号は presentation 完走後に退出する")
    func PB_TR_05_closureDuringPresentationWaitsForPresentation() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(
            transition: DialogTransition(
                presentation: probe.gatedHook(.presentation, gate: gate),
                dismissal: probe.immediateHook(.dismissal)
            )
        )

        try #require(await waitUntil { probe.hasEvent(.started(.presentation)) })
        try await stage.notifier().complete(true)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(probe.callCount(.dismissal) == 0, "presentation の完走前に退出は始まらない")

        gate.open()
        #expect(try await stage.task.value == .completed(true))
        #expect(probe.callCount(.dismissal) == 1)
        #expect(
            probe.events == [
                .started(.presentation),
                .finished(.presentation),
                .started(.dismissal),
                .finished(.dismissal)
            ]
        )
    }

    @Test("[PB-TR-06] 複数の閉鎖信号でも dismissal フックは1回")
    func PB_TR_06_dismissalHookRunsAtMostOnce() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        try await stage.notifier().complete(true)
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) })
        container.reportOutsideTap()

        gate.open()
        #expect(try await stage.task.value == .completed(true))
        #expect(probe.callCount(.dismissal) == 1)
    }

    @Test("[PB-TR-07] cancelled 経路 (外側タップ) でも dismissal フックが実行される")
    func PB_TR_07_outsideTapRunsDismissalHook() async throws {
        let probe = DialogTransitionProbe()
        let stage = try await start(transition: DialogTransition(dismissal: probe.immediateHook(.dismissal)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        container.reportOutsideTap()

        #expect(try await stage.task.value == .cancelled)
        #expect(probe.callCount(.dismissal) == 1)
    }

    @Test("[PB-TR-08] 呼び出し元キャンセルでも dismissal フックが実行され、形態ごとの規約で観察される")
    func PB_TR_08_callerCancellationRunsDismissalHook() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        stage.task.cancel()
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) }, "取り消しは退出の演出を始める")

        // 表示中の取り消しは脱出口ではないので、退出の演出は打ち切られず完走する。
        try? await Task.sleep(for: .milliseconds(150))
        #expect(probe.hasEvent(.finished(.dismissal)) == false, "門が開くまで演出は終わらない")
        #expect(probe.hasEvent(.cancelled(.dismissal)) == false, "演出は取り消されない")
        #expect(stage.harness.presentedContainers.count == 1, "演出の完了前は器が残っている")

        gate.open()
        #expect(try await stage.task.value == .cancelled, "Swift は show が cancelled を返す")
        #expect(
            probe.events == [.started(.dismissal), .finished(.dismissal)],
            "退出の演出は完走し、その完了は配送より先に起きる"
        )
        #expect(probe.callCount(.dismissal) == 1)
        let call = try #require(probe.firstCall(.dismissal))
        #expect(call.hostView === container.contentView)
        #expect(call.isOnWindow, "フックが始まる時点でホスト View はウィンドウ上にある")
        #expect(await stage.harness.waitForPresentedContainers(count: 0))
    }

    @Test("[PB-TR-09] OS 発の器消失ではフックを実行せず即 cancelled")
    func PB_TR_09_hostLossSkipsHooks() async throws {
        let probe = DialogTransitionProbe()
        let stage = try await start(
            transition: DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.immediateHook(.dismissal)
            )
        )

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        stage.harness.presentationSurface.simulateHostLoss(of: container)

        #expect(try await stage.task.value == .cancelled)
        #expect(probe.callCount(.dismissal) == 0)
        #expect(container.containerState == .removed)
        #expect(container.contentHost == nil, "ホストは解放される")
    }

    @Test("[PB-TR-19] 提示開始前の報告は演出なしで配送される")
    func PB_TR_19_reportBeforePresentationSkipsHooks() async throws {
        let probe = DialogTransitionProbe()
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        let task = show(
            harness: harness,
            recorder: recorder,
            transition: DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.immediateHook(.dismissal)
            ),
            reportsInFactory: true
        )

        #expect(try await task.value == .completed(true))
        #expect(probe.events.isEmpty, "両フックとも呼ばれない")
        #expect(await harness.waitForPresentedContainers(count: 0))
    }

    @Test("[PB-TR-20] 提示開始前の呼び出し元キャンセルは演出なしで閉じる")
    func PB_TR_20_callerCancellationBeforePresentationSkipsHooks() async throws {
        let probe = DialogTransitionProbe()
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.presentationSurface.holdsWindowAttachment = true
        let task = show(
            harness: harness,
            recorder: recorder,
            transition: DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.immediateHook(.dismissal)
            )
        )
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        try #require(container.containerState == .created, "まだ提示は始まっていない")

        // 取り消しは show が待ちに入った状態で届くため、この時点でキャンセルが確定する。
        task.cancel()
        harness.presentationSurface.attachHeldContainers()

        #expect(try await task.value == .cancelled)
        #expect(probe.events.isEmpty, "両フックとも呼ばれない")
    }

    /// 器を画面へ載せてから提示の進行が動き出すまでには1度の譲りがある。
    /// その隙間に届いた呼び出し元キャンセルも「表示前」の扱いになる。
    ///
    /// 隙間の間だけ段階が先に進んでいると、一度も見えていない中身に対して退出の演出が走る。
    /// 器を直接組み立て、進行が動き出す前の同期区間でそのまま取り消しを届けて確かめる。
    @Test("提示が動き出す前の呼び出し元キャンセルでは両フックとも実行されない")
    func callerCancellationBeforePresentationStartsSkipsHooks() async throws {
        let probe = DialogTransitionProbe()
        let contentView = FixedContentSizeView(contentSize: CGSize(width: 200, height: 120))
        contentView.ksDialogTransition = DialogTransition(
            presentation: probe.immediateHook(.presentation),
            dismissal: probe.immediateHook(.dismissal)
        )
        let resultChannel = DialogResultChannel()
        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.probeScreen,
            insets: Self.probeInsets,
            resultChannel: resultChannel
        )
        defer { stage.window.isHidden = true }
        let recorder = DialogOutcomeRecorder()
        stage.container.outcomeDelivery.setDestination { recorder.record($0) }

        // 器が進行を始めたのと同じ同期区間。提示はまだ動き出していない。
        #expect(stage.container.containerState == .attached, "提示が動き出すまでは載せただけの段階にいる")
        resultChannel.cancelFromCaller()
        stage.container.handleCallerCancellation()

        try #require(await waitUntil { stage.container.containerState == .removed })
        #expect(probe.events.isEmpty, "両フックとも呼ばれない")
        #expect(recorder.count == 1)
        #expect(recorder.isFirstCancelled, "演出なしで cancelled が配送される")
    }

    /// 同じ隙間に別のスレッドからの報告が届いた場合も「表示前」の扱いになる。
    ///
    /// 報告は結果チャネルへ直ちに確定として届く一方、器がそれを扱うのは次の譲りのあとなので、
    /// 進行の側でも確定済みかどうかを見る必要がある。
    @Test("提示が動き出す前の報告では両フックとも実行されず演出なしで配送される")
    func reportBeforePresentationStartsSkipsHooks() async throws {
        let probe = DialogTransitionProbe()
        let contentView = FixedContentSizeView(contentSize: CGSize(width: 200, height: 120))
        contentView.ksDialogTransition = DialogTransition(
            presentation: probe.immediateHook(.presentation),
            dismissal: probe.immediateHook(.dismissal)
        )
        let resultChannel = DialogResultChannel()
        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.probeScreen,
            insets: Self.probeInsets,
            resultChannel: resultChannel
        )
        defer { stage.window.isHidden = true }
        let recorder = DialogOutcomeRecorder()
        stage.container.outcomeDelivery.setDestination { recorder.record($0) }
        stage.container.observeResultChannel()

        #expect(stage.container.containerState == .attached, "提示が動き出すまでは載せただけの段階にいる")
        resultChannel.settle(.completed(true))

        try #require(await waitUntil { stage.container.containerState == .removed })
        #expect(probe.events.isEmpty, "両フックとも呼ばれない")
        #expect(recorder.count == 1)
        #expect(recorder.firstCompletedValue(as: Bool.self) == true, "演出なしで報告された結果が配送される")
    }

    /// 結果チャネルの観察が付いていない状態で確定した場合も「表示前」の扱いになる。
    ///
    /// 確定は観察の登録とは無関係にどのスレッドからでも起こり得るので、提示の進行は
    /// 取り消しの有無だけでなく結果が確定済みかどうかも自分で見る (core/ADR-0017)。
    /// 観察を登録しないことで、確定を受けて器を動かす仕掛けを進行側の判定だけに絞り、
    /// その判定単独で提示が取りやめになることを確かめる。
    @Test("観察が付かないまま確定した場合も提示は動き出さない")
    func settlementWithoutObserverStillSkipsPresentation() async throws {
        let probe = DialogTransitionProbe()
        let contentView = FixedContentSizeView(contentSize: CGSize(width: 200, height: 120))
        contentView.ksDialogTransition = DialogTransition(
            presentation: probe.immediateHook(.presentation),
            dismissal: probe.immediateHook(.dismissal)
        )
        let resultChannel = DialogResultChannel()
        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.probeScreen,
            insets: Self.probeInsets,
            resultChannel: resultChannel
        )
        defer { stage.window.isHidden = true }
        let recorder = DialogOutcomeRecorder()
        stage.container.outcomeDelivery.setDestination { recorder.record($0) }

        // 観察は登録しない (確定を扱う仕事が投入されない)。
        #expect(stage.container.containerState == .attached, "提示が動き出すまでは載せただけの段階にいる")
        resultChannel.settle(.completed(true))

        try #require(await waitUntil { stage.container.containerState == .removed })
        #expect(probe.events.isEmpty, "進行の側の確定判定だけで両フックが抑止される")
        #expect(recorder.count == 1)
        #expect(recorder.firstCompletedValue(as: Bool.self) == true, "演出なしで報告された結果が配送される")
    }

    @Test("[PB-TR-21] none 直後の閉鎖はオーバーレイの出現完了を待ってから退出する")
    func PB_TR_21_noneWaitsForOverlayAppearance() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        let task = show(harness: harness, recorder: recorder, transition: DialogTransition.none())
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        // 取り付け直後は .attached のことがある。覆いの出現 (.presenting) に入るまで待ってから閉じる
        try #require(await waitUntil { container.containerState == .presenting })

        try await recorder.notifier(at: 0).complete(true)
        #expect(container.containerState == .presenting, "覆いの出現中はまだ退出しない")

        #expect(try await task.value == .completed(true))
        #expect(container.containerState == .removed)
    }

    @Test("[PB-TR-28] presentation 中の呼び出し元キャンセルは presentation をキャンセルして退出する")
    func PB_TR_28_callerCancellationDuringPresentation() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(
            transition: DialogTransition(
                presentation: probe.gatedHook(.presentation, gate: gate),
                dismissal: probe.immediateHook(.dismissal)
            )
        )

        try #require(await waitUntil { probe.hasEvent(.started(.presentation)) })
        stage.task.cancel()

        #expect(try await stage.task.value == .cancelled)
        #expect(await waitUntilCancelled(probe, .presentation), "出現の演出は完走を待たずに取り消される")
        #expect(probe.hasEvent(.finished(.presentation)) == false)
        #expect(probe.callCount(.dismissal) == 1)
    }

    @Test("[PB-TR-29] 退出中の呼び出し元キャンセルは実行中の dismissal フックをキャンセルして脱出する")
    func PB_TR_29_callerCancellationDuringDismissal() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        try await stage.notifier().complete(true)
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) })
        stage.task.cancel()

        #expect(try await stage.task.value == .cancelled, "ラッチ済みの completed は呼び出し元へ届かない")
        #expect(await waitUntilCancelled(probe, .dismissal))
        #expect(probe.hasEvent(.finished(.dismissal)) == false)
        #expect(container.containerState == .removed)
    }

    @Test("[PB-TR-22] 退出中の入力は無視される")
    func PB_TR_22_inputDuringDismissalIsIgnored() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        try await stage.notifier().complete(true)
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) })

        #expect(container.view.isUserInteractionEnabled == false)
        #expect(container.view.hitTest(CGPoint(x: 5, y: 5), with: nil) == nil, "覆いも中身もタップを受け取らない")
        container.reportOutsideTap()
        try await stage.notifier().complete(false)

        gate.open()
        #expect(try await stage.task.value == .completed(true), "配送されるのは最初の報告の値")
    }

    // MARK: 結果のラッチと配送

    @Test("[PB-TR-10] show は dismissal フック完了と器の撤去より先に返らない")
    func PB_TR_10_deliveryWaitsForDismissalAndRemoval() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        let surface = stage.harness.presentationSurface
        try #require(await waitUntil(container, is: .shown))
        // 閉鎖の要求と実際の撤去完了を別々に進められるようにする。
        surface.holdsDismissalCompletion = true
        try await stage.notifier().complete(true)
        try? await Task.sleep(for: .milliseconds(150))

        #expect(stage.harness.presentedContainers.count == 1, "フック完了前は器が残っている")
        #expect(probe.hasEvent(.finished(.dismissal)) == false)
        #expect(surface.heldDismissalCount == 0, "フック完了前は閉鎖の要求も出ていない")

        gate.open()
        try #require(await waitUntil { surface.heldDismissalCount == 1 })
        try? await Task.sleep(for: .milliseconds(100))

        #expect(probe.hasEvent(.finished(.dismissal)), "フックは完了している")
        #expect(stage.harness.presentedContainers.count == 1, "撤去の完了通知が来るまで器は残っている")
        #expect(container.containerState == .dismissing, "撤去の完了通知が来るまでは撤去済みにならない")
        #expect(container.isOutcomeDelivered == false, "撤去が終わるまで結果は配送されない")

        surface.completeHeldDismissals()
        #expect(try await stage.task.value == .completed(true))
        #expect(container.isOutcomeDelivered)
        #expect(stage.harness.presentedContainers.isEmpty, "配送の時点で器は撤去済み")
    }

    @Test("[PB-TR-11] 退出中の二重報告はラッチ済みの値を配送する")
    func PB_TR_11_secondReportDuringDismissalIsIgnored() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        let notifier = try await stage.notifier()
        notifier.complete(true)
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) })
        notifier.complete(false)

        gate.open()
        #expect(try await stage.task.value == .completed(true))
    }

    @Test("[PB-TR-12] 退出中の OS 発器消失ではフックをキャンセルして即配送する")
    func PB_TR_12_hostLossDuringDismissalDeliversLatchedOutcome() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        try await stage.notifier().complete(true)
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) })
        stage.harness.presentationSurface.simulateHostLoss(of: container)

        #expect(try await stage.task.value == .completed(true), "cancelled には変わらない")
        #expect(await waitUntilCancelled(probe, .dismissal))
        #expect(probe.hasEvent(.finished(.dismissal)) == false)
        #expect(container.containerState == .removed)
    }

    @Test("[PB-TR-23] 提示中の OS 発器消失ではフックをキャンセルして cancelled を配送する")
    func PB_TR_23_hostLossDuringPresentationDeliversCancelled() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(presentation: probe.gatedHook(.presentation, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil { probe.hasEvent(.started(.presentation)) })
        stage.harness.presentationSurface.simulateHostLoss(of: container)

        #expect(try await stage.task.value == .cancelled)
        #expect(await waitUntilCancelled(probe, .presentation))
        #expect(container.containerState == .removed)
    }

    /// 配送は器の解放と競合しても取り残されない。
    ///
    /// 配送口は器とは別の寿命を持つため、器が撤去まで進めないまま解放されても
    /// ラッチ済みの結果が届く。器を握っている者がいない状態は show 越しには作れない
    /// (提示処理が結果を待つ間ずっと器を握っている) ので、器を直接組み立てて観察する。
    @Test("器が解放されてもラッチ済みの結果は配送される")
    func deliveryOutlivesContainerRelease() async throws {
        let resultChannel = DialogResultChannel()
        resultChannel.settle(.completed(true))
        let recorder = DialogOutcomeRecorder()

        weak var containerReference: DialogContainerViewController?
        do {
            let container = DialogContainerViewController(
                contentView: DialogTestContentView(),
                resultChannel: resultChannel
            )
            containerReference = container
            container.outcomeDelivery.setDestination { recorder.record($0) }
        }

        try #require(await waitUntil { containerReference == nil }, "器は解放されている")
        #expect(await waitUntil { recorder.count == 1 }, "呼び出し元は取り残されない")
        #expect(recorder.firstCompletedValue(as: Bool.self) == true, "ラッチ済みの結果がそのまま届く")
    }

    /// 配送のあとは誰も器を握り続けない。
    ///
    /// 撤去の完了を待つ間の後始末は器を強く捕まえて進めるため、その捕まえ方が
    /// 配送のあとも残らないことを固定する。
    @Test("[PB-TR-12] OS 発器消失の配送のあと器は解放される")
    func PB_TR_12_containerIsReleasedAfterHostLossDelivery() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        try #require(await waitUntil { stage.harness.topmostContainer?.containerState == .shown })
        try await stage.notifier().complete(true)
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) })
        // 器そのものはテスト側へ渡さず、面からも外して生存だけを観察する。
        let containerReference = try #require(
            stage.harness.presentationSurface.simulateHostLossOfTopmostContainer()
        )

        #expect(try await stage.task.value == .completed(true))
        #expect(await waitUntil { containerReference.isReleased }, "器を握り続ける者はいない")
    }

    @Test("[PB-TR-13] 添付なしの既定トランジションでも配送は撤去後")
    func PB_TR_13_defaultTransitionDeliversAfterRemoval() async throws {
        let stage = try await start(transition: nil)

        let container = try #require(stage.harness.topmostContainer)
        let surface = stage.harness.presentationSurface
        try #require(await waitUntil(container, is: .shown))
        surface.holdsDismissalCompletion = true
        try await stage.notifier().complete(true)

        // 既定の退出処理が終わっても、撤去の完了通知が来るまでは配送されない。
        try #require(await waitUntil { surface.heldDismissalCount == 1 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(stage.harness.presentedContainers.count == 1)
        #expect(container.containerState == .dismissing, "撤去の完了通知が来るまでは撤去済みにならない")
        #expect(container.isOutcomeDelivered == false)

        surface.completeHeldDismissals()
        #expect(try await stage.task.value == .completed(true))
        #expect(container.isOutcomeDelivered)
        #expect(stage.harness.presentedContainers.isEmpty)
    }

    // MARK: フックの失敗

    @Test("[PB-TR-14] presentation フックの失敗でも表示は継続する")
    func PB_TR_14_presentationFailureKeepsDialogShown() async throws {
        let probe = DialogTransitionProbe()
        let stage = try await start(transition: DialogTransition(presentation: probe.failingHook(.presentation)))

        let container = try #require(stage.harness.topmostContainer)
        #expect(await waitUntil(container, is: .shown), "失敗しても表示状態へ進む")

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
    }

    @Test("[PB-TR-15] dismissal フックの失敗でも撤去と配送は完了する")
    func PB_TR_15_dismissalFailureStillRemovesAndDelivers() async throws {
        let probe = DialogTransitionProbe()
        let stage = try await start(transition: DialogTransition(dismissal: probe.failingHook(.dismissal)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        try await stage.notifier().complete(true)

        #expect(try await stage.task.value == .completed(true))
        #expect(stage.harness.presentedContainers.isEmpty)
    }

    // MARK: フックの完了は利用者の責務

    @Test("[PB-TR-24] 終了しないフックは呼び出し元キャンセルで脱出できる")
    func PB_TR_24_neverFinishingHookEscapesByCallerCancellation() async throws {
        let probe = DialogTransitionProbe()
        // 開けない門で「決して完了しないフック」を作る。
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        try await stage.notifier().complete(true)
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) })
        stage.task.cancel()

        #expect(try await stage.task.value == .cancelled)
        #expect(probe.hasEvent(.finished(.dismissal)) == false, "フックは完了していない")
        #expect(stage.harness.presentedContainers.isEmpty, "それでも器は撤去される")
    }

    @Test("[PB-TR-25] 終了しないフックは OS 発の器消失で脱出できる")
    func PB_TR_25_neverFinishingHookEscapesByHostLoss() async throws {
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()
        let stage = try await start(transition: DialogTransition(dismissal: probe.gatedHook(.dismissal, gate: gate)))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))
        try await stage.notifier().complete(true)
        try #require(await waitUntil { probe.hasEvent(.started(.dismissal)) })
        stage.harness.presentationSurface.simulateHostLoss(of: container)

        #expect(try await stage.task.value == .completed(true))
        #expect(probe.hasEvent(.finished(.dismissal)) == false)
        #expect(container.containerState == .removed)
    }

    // MARK: プリセット

    @Test("[PB-TR-16] プリセット指定で追加のフック記述なしにトランジションが差し替わり、覆いの時間も揃う")
    func PB_TR_16_slidePresetDrivesTransitionAndOverlay() async throws {
        let duration: TimeInterval = 0.08
        let stage = try await start(transition: DialogTransition.slide(from: .bottom, duration: duration))

        let container = try #require(stage.harness.topmostContainer)
        #expect(container.resolvedOverlayDuration == duration, "覆いのフェード時間はプリセットの時間と同じ")
        try #require(await waitUntil(container, is: .shown))
        #expect(container.contentView.transform == .identity, "出現の演出は最終状態で終わる")

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
    }

    @Test("[PB-TR-17] none プリセットではコンテンツ側の待ちなしで表示・閉鎖される")
    func PB_TR_17_nonePresetHasNoContentAnimation() async throws {
        let stage = try await start(transition: DialogTransition.none())

        let container = try #require(stage.harness.topmostContainer)
        #expect(container.resolvedOverlayDuration == DialogTransition.defaultDuration, "覆いは既定の時間で扱われる")
        try #require(await waitUntil(container, is: .shown))

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
    }

    @Test("[PB-TR-18] duration 0 のプリセットは即完了する")
    func PB_TR_18_zeroDurationPresetCompletesImmediately() async throws {
        let stage = try await start(transition: DialogTransition.fade(duration: 0))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
    }

    @Test("[PB-TR-26] 負の duration のプリセットは即完了する")
    func PB_TR_26_negativeDurationPresetCompletesImmediately() async throws {
        let stage = try await start(transition: DialogTransition.slide(from: .top, duration: -1))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown))

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
    }

    @Test(
        "[PB-TR-27] 有効範囲外の duration のプリセットは即完了する",
        arguments: [TimeInterval.nan, TimeInterval.infinity, -TimeInterval.infinity]
    )
    func PB_TR_27_outOfRangeDurationPresetCompletesImmediately(duration: TimeInterval) async throws {
        let stage = try await start(transition: DialogTransition.zoom(duration: duration))

        let container = try #require(stage.harness.topmostContainer)
        try #require(await waitUntil(container, is: .shown), "覆いも即完了する")

        try await stage.notifier().complete(true)
        #expect(try await stage.task.value == .completed(true))
    }

    // MARK: 組み立て

    /// 1回分の show とその観測に必要な道具。
    private struct Stage {
        let harness: DialogTestHarness
        let recorder: DialogTestRecorder<Bool>
        let task: Task<DialogResult<Bool>, any Error>

        /// この show の結果報告口。
        func notifier() async throws -> DialogNotifier<Bool> {
            try await recorder.notifier(at: 0)
        }
    }

    /// 演出を添付したダイアログを1枚表示し、器が画面に載るまで待つ。
    private func start(transition: DialogTransition?) async throws -> Stage {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        let task = show(harness: harness, recorder: recorder, transition: transition)
        try #require(await harness.waitForPresentedContainers(count: 1))
        return Stage(harness: harness, recorder: recorder, task: task)
    }

    /// 演出を添付した中身で show を始める。
    private func show(
        harness: DialogTestHarness,
        recorder: DialogTestRecorder<Bool>,
        transition: DialogTransition?,
        reportsInFactory: Bool = false
    ) -> Task<DialogResult<Bool>, any Error> {
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            view.ksDialogTransition = transition
            recorder.record(view: view, notifier: notifier)
            if reportsInFactory {
                notifier.complete(true)
            }
            return view
        }
        return Task {
            try await harness.dialogs.show(BasicTestDialogViewModel(message: ""))
        }
    }

    /// 器が指定の段階になるまで待つ。
    private func waitUntil(_ container: DialogContainerViewController, is state: DialogContainerState) async -> Bool {
        await DialogTestWaiting.waitUntil { container.containerState == state }
    }

    /// 条件が満たされるまで待つ。
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        await DialogTestWaiting.waitUntil(condition)
    }

    /// フックが取り消されたことが記録されるまで待つ。
    ///
    /// 門で待っているフックの取り消しは、取り消しの受け口が改めて立てる仕事の中で
    /// `CancellationError` として届く。結果の配送はそれとは別の経路で進むため、
    /// 「結果が配送された時点で記録も入っている」とは限らない。
    private func waitUntilCancelled(
        _ probe: DialogTransitionProbe,
        _ phase: DialogTransitionProbe.Phase
    ) async -> Bool {
        await waitUntil { probe.hasEvent(.cancelled(phase)) }
    }
}
#endif
