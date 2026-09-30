#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 提示先の出現を待つ Dialog の結末を確かめる。
///
/// 提示先が無いまま呼ばれた show は失敗せず、結果報告口を紐付けたうえで提示先の出現を待つ。
/// 待ちは、提示先が現れて列の先頭に来たとき・呼び出し元が打ち切ったとき・待っている間に
/// 結果が確定したときのどれかで明ける。待っている Dialog は呼んだ順に 1 枚ずつ明ける。
@Suite("提示先の出現を待つ Dialog", .serialized)
@MainActor
struct DialogHostWaitTests {
    /// 提示先の無い組み立てと、View factory の呼び出しの記録。
    /// 作った中身には ViewModel の message を識別子として付け、表示の順を message で読めるようにする。
    private static func makeHarnessWithoutHost() -> (DialogTestHarness, DialogTestRecorder<Bool>) {
        let harness = DialogTestHarness(hasPresentationHost: false)
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { viewModel, notifier in
            let view = DialogTestContentView()
            view.accessibilityIdentifier = viewModel.message
            recorder.record(view: view, notifier: notifier)
            return view
        }
        return (harness, recorder)
    }

    /// 列に並んだ show の数が期待どおりになるまで待つ。
    private static func waitForWaitingCount(_ count: Int, in harness: DialogTestHarness) async -> Bool {
        await DialogTestWaiting.waitUntil { harness.presentationSurface.hostWaitQueue.waitingCount == count }
    }

    /// 下から順に並んだ、表示中のダイアログの中身の識別子 (ViewModel の message)。
    private static func presentedMessages(in harness: DialogTestHarness) -> [String?] {
        harness.presentedContainers.map { $0.contentView.accessibilityIdentifier }
    }

    /// 提示先を用意してから、提示先の出現の合図を送る。
    private static func makeHostAppear(in harness: DialogTestHarness) {
        harness.presentationSurface.isPresentationHostAvailable = true
        harness.presentationSurface.fireHostAppearance()
    }

    @Test("[PB-HW-02] 待っている間に呼び出し元が打ち切ると、一度も表示されずに終わる")
    func PB_HW_02_callerCancellationWhileWaitingEndsWithoutPresenting() async throws {
        let (harness, recorder) = Self.makeHarnessWithoutHost()
        let viewModel = BasicTestDialogViewModel(message: "打ち切られる")

        let showTask = Task { try await harness.dialogs.show(viewModel) }
        try #require(await Self.waitForWaitingCount(1, in: harness))

        showTask.cancel()

        #expect(try await showTask.value == .cancelled, "打ち切りは cancelled として返る")
        #expect(viewModel.notifier == nil, "VM の紐付けは解除されている")
        #expect(harness.presentationSurface.hostWaitQueue.waitingCount == 0, "列から外れている")

        Self.makeHostAppear(in: harness)
        await Task.yield()

        #expect(recorder.createdViews.isEmpty, "View factory は一度も呼ばれない")
        #expect(harness.presentedContainers.isEmpty, "提示先が現れても表示されない")
        #expect(harness.presentationSurface.hostAppearance.activeRegistrationCount == 0, "購読は解除されている")
    }

    @Test("[PB-HW-03] 待っている間に VM が結果を報告すると、表示されずにその結果が返る")
    func PB_HW_03_reportWhileWaitingReturnsResultWithoutPresenting() async throws {
        let (harness, recorder) = Self.makeHarnessWithoutHost()
        let viewModel = BasicTestDialogViewModel(message: "表示の前に報告する")

        let showTask = Task { try await harness.dialogs.show(viewModel) }
        try #require(await Self.waitForWaitingCount(1, in: harness))

        let notifier = try #require(viewModel.notifier, "待っている間も VM の報告口は紐付いている")
        notifier.complete(true)

        #expect(try await showTask.value == .completed(true), "報告した結果がそのまま返る")
        #expect(harness.presentationSurface.hostWaitQueue.waitingCount == 0, "列から外れている")

        Self.makeHostAppear(in: harness)
        await Task.yield()

        #expect(recorder.createdViews.isEmpty, "View factory は一度も呼ばれない")
        #expect(harness.presentedContainers.isEmpty, "ダイアログは表示されない")
    }

    @Test("[PB-HW-04] 未登録の ViewModel 型は、提示先が無くても待たずに失敗する")
    func PB_HW_04_unregisteredViewModelFailsWithoutWaiting() async throws {
        let (harness, _) = Self.makeHarnessWithoutHost()

        await #expect(
            throws: DialogError.viewFactoryNotRegistered(viewModelType: "UnregisteredTestDialogViewModel")
        ) {
            _ = try await harness.dialogs.show(UnregisteredTestDialogViewModel())
        }
        #expect(harness.presentationSurface.hostWaitQueue.waitingCount == 0, "列に並ばない")
        #expect(harness.presentationSurface.hostAppearance.totalRegistrationCount == 0, "合図も購読しない")
    }

    @Test("[PB-HW-05] 待っている間の同じ VM インスタンスの再 show は「表示中」として失敗する")
    func PB_HW_05_reshowingWaitingViewModelFailsAsAlreadyShowing() async throws {
        let (harness, recorder) = Self.makeHarnessWithoutHost()
        let viewModel = BasicTestDialogViewModel(message: "待っている")

        let firstShow = Task { try await harness.dialogs.show(viewModel) }
        try #require(await Self.waitForWaitingCount(1, in: harness))

        await #expect(
            throws: DialogError.viewModelAlreadyShowing(viewModelType: "BasicTestDialogViewModel")
        ) {
            _ = try await harness.dialogs.show(viewModel)
        }
        #expect(harness.presentationSurface.hostWaitQueue.waitingCount == 1, "1 回目の待ちは続く")

        // 1 回目は提示先が現れた時点で表示され、ふつうに結果を返す。
        Self.makeHostAppear(in: harness)
        let notifier = try await recorder.notifier(at: 0)
        notifier.complete(false)
        #expect(try await firstShow.value == .completed(false))
    }

    @Test("[PB-HW-06] 待っている Dialog が複数あると、呼んだ順に表示され、後から呼んだものが手前になる")
    func PB_HW_06_waitingDialogsArePresentedInCallOrder() async throws {
        let (harness, recorder) = Self.makeHarnessWithoutHost()
        let viewModelA = BasicTestDialogViewModel(message: "A")
        let viewModelB = BasicTestDialogViewModel(message: "B")

        // UI スレッドから、間に待ち合わせを挟まずに A、B の順で呼ぶ。
        let showA = Task { try await harness.dialogs.show(viewModelA) }
        let showB = Task { try await harness.dialogs.show(viewModelB) }
        try #require(await Self.waitForWaitingCount(2, in: harness))

        Self.makeHostAppear(in: harness)

        try #require(await harness.waitForPresentedContainers(count: 2), "2 枚とも表示される")
        #expect(Self.presentedMessages(in: harness) == ["A", "B"], "呼んだ順に表示され、B が A の手前に重なる")
        let notifierA = try #require(viewModelA.notifier)
        let notifierB = try #require(viewModelB.notifier)
        #expect(recorder.createdViews.count == 2)
        #expect(harness.presentedContainers[0].contentView === recorder.createdViews[0], "A が先に表示される")
        #expect(harness.presentedContainers[1].contentView === recorder.createdViews[1], "B が A の手前に重なる")
        #expect(harness.presentationSurface.hostAppearance.activeRegistrationCount == 0, "待つ表示が無くなれば購読を解除する")

        // それぞれが独立に結果を返す。
        notifierB.complete(true)
        #expect(try await showB.value == .completed(true))
        notifierA.complete(false)
        #expect(try await showA.value == .completed(false))
    }

    /// UI スレッドで同期的に始まる Task から呼ぶと、show が最初に中断するまでを呼び出しの中で観察できる。
    /// show が UI スレッドの外へ移ってから戻る作りだと、呼び出しから戻った時点ではまだ列に並んでいない。
    @Test("[PB-HW-06] UI スレッドから続けて呼んだ show は、呼び出しから戻る前に呼んだ順で列に並ぶ")
    @available(iOS 26.0, *)
    func PB_HW_06_showsCalledOnMainActorQueueBeforeReturning() async throws {
        let (harness, recorder) = Self.makeHarnessWithoutHost()
        let viewModelA = BasicTestDialogViewModel(message: "A")
        let viewModelB = BasicTestDialogViewModel(message: "B")

        // A は具体型の入口、B は DI で受け取る契約 (`KsDialog`) の入口から呼び、どちらの経路も確かめる。
        let injected: any KsDialog = harness.dialogs
        let showA = Task.immediate { try await harness.dialogs.show(viewModelA, placement: nil) }
        let showB = Task.immediate { try await injected.show(viewModelB) }
        #expect(
            harness.presentationSurface.hostWaitQueue.waitingCount == 2,
            "UI スレッドを離れずに列まで進み、2 件とも並んでいる"
        )

        Self.makeHostAppear(in: harness)

        try #require(await harness.waitForPresentedContainers(count: 2), "2 枚とも表示される")
        #expect(recorder.createdViews.map(\.accessibilityIdentifier) == ["A", "B"], "A の中身が先に作られる")
        #expect(Self.presentedMessages(in: harness) == ["A", "B"], "呼んだ順に表示され、B が A の手前に重なる")

        try #require(viewModelB.notifier).complete(true)
        #expect(try await showB.value == .completed(true))
        try #require(viewModelA.notifier).complete(false)
        #expect(try await showA.value == .completed(false))
    }

    @Test("[PB-HW-08] 待っている Dialog があるうちに呼んだ show は、追い越さずに後ろに並ぶ")
    func PB_HW_08_showDuringReleasedPresentationQueuesBehind() async throws {
        let (harness, recorder) = Self.makeHarnessWithoutHost()
        let viewModelA = BasicTestDialogViewModel(message: "A")
        let viewModelB = BasicTestDialogViewModel(message: "B")
        let viewModelC = BasicTestDialogViewModel(message: "C")

        let showA = Task { try await harness.dialogs.show(viewModelA) }
        try #require(await Self.waitForWaitingCount(1, in: harness))

        // A の提示は始まったが、まだ終わっていない状態を作る。
        harness.presentationSurface.holdsPresentationCompletion = true
        Self.makeHostAppear(in: harness)
        try #require(await harness.waitForPresentedContainers(count: 1), "A の提示が始まる")
        try #require(harness.presentationSurface.heldPresentationCompletionCount == 1)

        // A の提示中に、間に待ち合わせを挟まずに B、C の順で呼ぶ。
        let showB = Task { try await harness.dialogs.show(viewModelB) }
        let showC = Task { try await harness.dialogs.show(viewModelC) }
        try #require(
            await Self.waitForWaitingCount(2, in: harness),
            "提示先があっても、A の提示が終わるまでは後ろに並ぶ"
        )
        #expect(recorder.createdViews.count == 1, "B・C の中身はまだ作られない")
        #expect(harness.presentedContainers.count == 1)

        harness.presentationSurface.holdsPresentationCompletion = false
        harness.presentationSurface.completeHeldPresentations()

        try #require(await harness.waitForPresentedContainers(count: 3), "A の提示が終わってから B、C が表示される")
        let notifierB = try #require(viewModelB.notifier)
        let notifierC = try #require(viewModelC.notifier)
        #expect(Self.presentedMessages(in: harness) == ["A", "B", "C"], "B、C の順に、A の手前へ重なる")

        notifierC.complete(true)
        #expect(try await showC.value == .completed(true))
        notifierB.complete(true)
        #expect(try await showB.value == .completed(true))
        try #require(viewModelA.notifier).complete(true)
        #expect(try await showA.value == .completed(true))
    }

    @Test("先に取られた順番札が列に着くまでは、提示先があっても後の show は明けず、札を手放すと明ける")
    func showWaitsBehindEarlierReservationUntilReleased() async throws {
        let (harness, _) = Self.makeHarnessWithoutHost()
        harness.presentationSurface.isPresentationHostAvailable = true
        let viewModel = BasicTestDialogViewModel(message: "A")

        let reservation = DialogPresenter.reserveTurn(on: harness.presentationSurface)
        let showA = Task { try await harness.dialogs.show(viewModel) }
        try #require(
            await Self.waitForWaitingCount(2, in: harness),
            "未着の札と、その後ろで待つ A が数えられる"
        )
        #expect(harness.presentedContainers.isEmpty, "先の札を追い越して表示しない")

        reservation.release()

        try #require(await harness.waitForPresentedContainers(count: 1), "札を手放すと A が表示される")
        #expect(Self.presentedMessages(in: harness) == ["A"])
        #expect(harness.presentationSurface.hostWaitQueue.waitingCount == 0)
        try #require(viewModel.notifier).complete(true)
        #expect(try await showA.value == .completed(true))
    }

    @Test("使われずに捨てられた順番札は、解放された時点で手放される")
    func discardedReservationIsReleasedOnDeinit() async throws {
        let (harness, _) = Self.makeHarnessWithoutHost()
        harness.presentationSurface.isPresentationHostAvailable = true
        let viewModel = BasicTestDialogViewModel(message: "A")

        var reservation: DialogHostWaitReservation? = DialogPresenter.reserveTurn(on: harness.presentationSurface)
        let showA = Task { try await harness.dialogs.show(viewModel) }
        try #require(await Self.waitForWaitingCount(2, in: harness))
        #expect(reservation != nil)

        reservation = nil

        try #require(await harness.waitForPresentedContainers(count: 1), "札が解放されると A が表示される")
        try #require(viewModel.notifier).complete(true)
        #expect(try await showA.value == .completed(true))
    }

    @Test("[PB-HW-07] 型指定 show の VM factory と configure は、待つ前に実行される")
    func PB_HW_07_typedShowRunsFactoryAndConfigureBeforeWaiting() async throws {
        let harness = DialogTestHarness(hasPresentationHost: false)
        let viewModelFactoryCalls = DialogTestCallCounter()
        let configureCalls = DialogTestCallCounter()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(ConfigurableTestDialogViewModel.self) {
            viewModelFactoryCalls.increment()
            return ConfigurableTestDialogViewModel()
        }
        harness.registry.register(ConfigurableTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task {
            try await harness.dialogs.show(ConfigurableTestDialogViewModel.self) { viewModel in
                configureCalls.increment()
                viewModel.message = "configure で設定"
            }
        }
        try #require(await Self.waitForWaitingCount(1, in: harness))

        #expect(viewModelFactoryCalls.count == 1, "VM factory は提示先が現れる前に実行されている")
        #expect(configureCalls.count == 1, "configure は提示先が現れる前に実行されている")
        #expect(recorder.createdViews.isEmpty, "View factory は提示先が現れるまで呼ばれない")

        Self.makeHostAppear(in: harness)
        let notifier = try await recorder.notifier(at: 0)
        notifier.complete(true)

        #expect(try await showTask.value == .completed(true))
        #expect(viewModelFactoryCalls.count == 1)
        #expect(configureCalls.count == 1)
    }
}
#endif
