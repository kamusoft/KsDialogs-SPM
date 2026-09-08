#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Loading の公開面と合流の契約 (core/ADR-0024) を確かめる。
///
/// 表示は 1 プロセスに 1 つで、重なった利用は 1 つの表示に合流する。
/// 渡された処理は表示状態によらず必ず実行され、失敗も合流1件の終了として数える。
@Suite("Loading の公開面と合流", .serialized)
@MainActor
struct LoadingCoalescingTests {
    // MARK: - 表示の出し入れ

    @Test("[LD-CO-01] show で表示され hide で消える")
    func LD_CO_01_showPresentsAndHideRemoves() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        await harness.loading.show()

        #expect(harness.isPresenting, "show が戻った時点で器は取り付いている")
        let contentView = try #require(harness.contentView)
        #expect(contentView.window === harness.window)
        #expect(harness.attachedContainerViews.count == 1)

        await harness.loading.hide()

        #expect(harness.isPresenting == false)
        #expect(contentView.window == nil)
        #expect(harness.attachedContainerViews.isEmpty)
    }

    @Test("[LD-CO-02] スコープ形は処理完了で自動的に閉じ、処理の戻り値を返す")
    func LD_CO_02_scopeClosesOnCompletionAndReturnsValue() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let gate = DialogTransitionGate()

        let scope = Task {
            try await harness.loading.start { _ in
                try await gate.wait()
                return 42
            }
        }

        try #require(await harness.waitUntilPresenting(), "処理の実行中は表示される")
        gate.open()

        #expect(try await scope.value == 42)
        #expect(harness.isPresenting == false)
    }

    @Test("[LD-CO-03] 重なったスコープ形は1つの表示に合流し、最後の完了で閉じる")
    func LD_CO_03_overlappingScopesCoalesceIntoSingleDisplay() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let firstGate = DialogTransitionGate()
        let secondGate = DialogTransitionGate()

        let first = Task {
            try await harness.loading.start { _ in try await firstGate.wait() }
        }
        try #require(await harness.waitUntilPresenting())
        let second = Task {
            try await harness.loading.start { _ in try await secondGate.wait() }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.coalescedUseCount == 2 })

        #expect(harness.attachedContainerViews.count == 1, "表示は1つに合流する")

        firstGate.open()
        try await first.value
        #expect(harness.isPresenting, "先の完了では消えない")

        secondGate.open()
        try await second.value
        #expect(harness.isPresenting == false, "後の完了で消える")
    }

    @Test("[LD-CO-04] 表示中でも渡した処理は必ず実行される")
    func LD_CO_04_actionRunsWhileAlreadyPresenting() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        await harness.loading.show()
        let didRun = try await harness.loading.start { _ in true }

        #expect(didRun)
        #expect(harness.isPresenting, "show の合流が残るため表示は継続する")
        await harness.loading.hide()
    }

    @Test("[LD-CO-05] 処理の失敗は合流1件の終了として数え、呼び出し元へ伝播する")
    func LD_CO_05_failureIsCountedAsEndAndPropagates() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        await #expect(throws: LoadingTestScopeError.failed) {
            try await harness.loading.start { _ in
                throw LoadingTestScopeError.failed
            }
        }

        #expect(harness.isPresenting == false, "失敗でも閉じ漏れしない")
        #expect(harness.coordinator.coalescedUseCount == 0)
    }

    @Test("[LD-CO-06] hide は合流数によらず即閉じ、走行中の処理は継続する")
    func LD_CO_06_hideClosesImmediatelyAndRunningActionContinues() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let gate = DialogTransitionGate()
        let recorder = LoadingTestActionRecorder()

        let scope = Task {
            try await harness.loading.start { _ in
                try await gate.wait()
                await recorder.recordCompletion()
                return true
            }
        }
        try #require(await harness.waitUntilPresenting())

        await harness.loading.hide()
        #expect(harness.isPresenting == false)
        #expect(recorder.completionCount == 0, "処理はまだ走っている")

        gate.open()
        #expect(try await scope.value)
        #expect(recorder.completionCount == 1, "処理は継続して完了する")
        #expect(harness.isPresenting == false, "完了で表示が再出現しない")
    }

    // MARK: - メッセージ

    @Test("[LD-CO-07] メッセージは後勝ち")
    func LD_CO_07_latestMessageWins() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        await harness.loading.show(message: "A")
        #expect(harness.builtinText == "A")

        await harness.loading.show(message: "B")
        #expect(harness.builtinText == "B")
        #expect(harness.coordinator.coalescedUseCount == 2)

        await harness.loading.hide()
    }

    @Test("[LD-CO-08] setMessage は表示中のみ有効で合流に関与しない")
    func LD_CO_08_setMessageAppliesOnlyWhilePresenting() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        // 非表示中は何も起こらない。
        await harness.loading.setMessage("ignored")
        #expect(harness.isPresenting == false)
        #expect(harness.coordinator.coalescedUseCount == 0)

        await harness.loading.show(message: "A")
        await harness.loading.setMessage("B")

        #expect(harness.builtinText == "B")
        #expect(harness.coordinator.coalescedUseCount == 1, "setMessage は合流を増やさない")

        // hide の対応は要らず、1件だけの hide で閉じる。
        await harness.loading.hide()
        #expect(harness.isPresenting == false)
    }

    // MARK: - コンテンツの決まり方

    @Test("[LD-CO-09] コンテンツは最初の開始が決める")
    func LD_CO_09_firstUseDecidesContent() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: CGSize(width: 120, height: 80))
            viewRecorder.record(view)
            return view
        }
        let customGate = DialogTransitionGate()
        let builtinGate = DialogTransitionGate()

        let custom = Task {
            try await harness.loading.start(LoadingTestViewModel()) { _ in
                try await customGate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        let builtin = Task {
            try await harness.loading.start { _ in try await builtinGate.wait() }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.coalescedUseCount == 2 })

        #expect(harness.contentView === viewRecorder.lastView, "表示はカスタム View のまま合流する")
        #expect(harness.coordinator.presentedBuiltinContentView == nil)

        builtinGate.open()
        try await builtin.value
        #expect(harness.isPresenting)

        customGate.open()
        try await custom.value
        #expect(harness.isPresenting == false, "両方の終了で表示が消える")
    }

    // MARK: - 表示世代

    @Test("[LD-CO-10] hide 後の新しい表示は旧世代の完了で閉じない")
    func LD_CO_10_staleGenerationCompletionDoesNotCloseNewDisplay() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let gateA = DialogTransitionGate()
        let gateB = DialogTransitionGate()

        let scopeA = Task {
            try await harness.loading.start { _ in
                try await gateA.wait()
                return "A"
            }
        }
        try #require(await harness.waitUntilPresenting())
        await harness.loading.hide()

        let scopeB = Task {
            try await harness.loading.start { _ in
                try await gateB.wait()
                return "B"
            }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.coalescedUseCount == 1 })
        try #require(harness.isPresenting)

        gateA.open()
        #expect(try await scopeA.value == "A", "旧世代の戻り値は元の呼び出し元へ返る")
        #expect(harness.isPresenting, "A の完了で B の表示は閉じない")

        gateB.open()
        #expect(try await scopeB.value == "B")
        #expect(harness.isPresenting == false, "B の完了で閉じる")
    }

    @Test("[LD-CO-11] 旧世代の遅延進捗・メッセージは新しい表示に届かない")
    func LD_CO_11_staleGenerationReportsDoNotReachNewDisplay() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let gateA = DialogTransitionGate()
        let gateB = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scopeA = Task {
            try await harness.loading.start(message: "A") { report in
                await reporter.capture(report)
                try await gateA.wait()
            }
        }
        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })
        await harness.loading.hide()

        let scopeB = Task {
            try await harness.loading.start(message: "B") { report in
                report(0.5)
                try await gateB.wait()
            }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "B\n50%" })

        // 旧世代の A から報告する。受理は UI スレッドへ移して行われるため、
        // 届く可能性のある猶予を与えてから観察する。
        reporter.report(0.9)
        _ = await DialogTestWaiting.waitUntil(timeout: .milliseconds(200)) {
            harness.builtinText != "B\n50%"
        }

        #expect(harness.builtinText == "B\n50%", "新世代の表示内容は変わらない")
        #expect(harness.coordinator.coalescedUseCount == 1, "旧世代の利用は新世代のカウントに入らない")

        gateA.open()
        try await scopeA.value
        gateB.open()
        try await scopeB.value
    }

    // MARK: - 完了時点

    @Test("[LD-CO-12] hide と最終 start は撤去完了後に戻る")
    func LD_CO_12_hideReturnsAfterRemovalCompletes() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let outsidePoint = CGPoint(x: 5, y: 5)

        await harness.loading.show()
        let containerView = try #require(harness.containerView)
        try #require(harness.window.hitTest(outsidePoint, with: nil) === containerView)

        await harness.loading.hide()

        #expect(containerView.superview == nil, "戻った時点で器は撤去済み")
        #expect(
            harness.window.hitTest(outsidePoint, with: nil) !== containerView,
            "操作ブロックは解除されている"
        )

        // 合流最後の start も同じく撤去の完了まで待って戻る。
        let observer = LoadingTestContainerObserver()
        try await harness.loading.start { _ in
            await observer.captureContainerView(of: harness)
        }
        let scopeContainerView = try #require(observer.containerViewDuringAction)
        #expect(scopeContainerView.superview == nil)
        #expect(harness.window.hitTest(outsidePoint, with: nil) !== scopeContainerView)
    }

    @Test("[LD-CO-13] 出の途中の新しい開始は出の完了後に新世代として表示される")
    func LD_CO_13_startDuringDismissalWaitsForCompletion() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        await harness.loading.show(message: "A")
        let firstContainerView = try #require(harness.containerView)

        let hiding = Task { await harness.loading.hide() }
        // 出の演出が始まっていることを確かめてから、新しい表示を開始する。
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.isDismissing })
        await harness.loading.show()
        await hiding.value

        let secondContainerView = try #require(harness.containerView)
        #expect(secondContainerView !== firstContainerView, "新世代として器が作り直される")
        #expect(firstContainerView.superview == nil, "旧世代は撤去されている")
        #expect(harness.attachedContainerViews.count == 1)
        #expect(harness.builtinText == nil, "旧世代のメッセージを引き継がない")

        await harness.loading.hide()
    }

    // MARK: - 提示環境と入口

    @Test("[LD-CO-14] 提示環境が無くても action は実行される")
    func LD_CO_14_actionRunsWithoutPresentationHost() async throws {
        let harness = LoadingTestHarness(hasHost: false)
        defer { harness.tearDown() }

        let value = try await harness.loading.start { _ in 7 }

        #expect(value == 7, "表示の不成立を理由に保留・放棄されない")
        #expect(harness.isPresenting == false)
        #expect(harness.attachedContainerViews.isEmpty)
    }

    @Test("[LD-CO-15] 異なる入口からの利用は1つの表示に合流する")
    func LD_CO_15_differentEntriesShareSingleDisplay() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        // 契約 interface から構築した別インスタンス (DI 注入で使う形)。
        let injected: any KsLoading = Loading(coordinator: harness.coordinator)
        let gate = DialogTransitionGate()

        await harness.loading.show(message: "A")
        let scope = Task {
            try await injected.start(message: "B") { _ in try await gate.wait() }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.coalescedUseCount == 2 })

        #expect(harness.attachedContainerViews.count == 1, "入口ごとに別の表示は出ない")
        #expect(harness.builtinText == "B")

        gate.open()
        try await scope.value
        #expect(harness.isPresenting, "最後の終了まで表示は続く")

        await injected.hide()
        #expect(harness.isPresenting == false)

        // 既定の入口どうしは同じ状態の正を指す。
        #expect(Loading().coordinator === Loading.shared.coordinator)
    }
}
#endif
