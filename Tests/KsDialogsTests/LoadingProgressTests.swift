#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// スコープ形の進捗通知 (core/ADR-0023・0024) を確かめる。
///
/// 値は 0〜1 にクランプされ、非有限値は無視される。表示は最新の報告が勝ち、
/// 既定ローディングではフォーマット関数の結果が、カスタム View では進捗受け口が受け取る。
@Suite("Loading の進捗通知", .serialized)
@MainActor
struct LoadingProgressTests {
    private static let contentSize = CGSize(width: 120, height: 80)

    @Test("[LD-PR-01] 進捗報告で既定ローディングの表示が更新される")
    func LD_PR_01_progressUpdatesBuiltinText() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start(message: "読み込み中") { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })

        reporter.report(0.45)

        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "読み込み中\n45%" })

        gate.open()
        try await scope.value
    }

    @Test("[LD-PR-02] 未報告のあいだはメッセージのみが表示される")
    func LD_PR_02_messageOnlyWhileProgressIsUnreported() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let gate = DialogTransitionGate()

        let scope = Task {
            try await harness.loading.start(message: "読み込み中") { _ in
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())

        #expect(harness.builtinText == "読み込み中", "既定のフォーマットは進捗なしならメッセージだけを返す")

        gate.open()
        try await scope.value
    }

    @Test("[LD-PR-03] 合流中は最新の報告が表示される")
    func LD_PR_03_latestReportWinsWhileCoalesced() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let firstGate = DialogTransitionGate()
        let secondGate = DialogTransitionGate()
        let firstReporter = LoadingTestProgressReporter()
        let secondReporter = LoadingTestProgressReporter()

        let first = Task {
            try await harness.loading.start(message: "読み込み中") { report in
                await MainActor.run { firstReporter.capture(report) }
                try await firstGate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        let second = Task {
            try await harness.loading.start { report in
                await MainActor.run { secondReporter.capture(report) }
                try await secondGate.wait()
            }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.coalescedUseCount == 2 })
        try #require(await DialogTestWaiting.waitUntil { secondReporter.isCaptured })

        firstReporter.report(0.2)
        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "読み込み中\n20%" })

        secondReporter.report(0.7)
        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "読み込み中\n70%" })

        firstReporter.report(0.3)
        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "読み込み中\n30%" })

        firstGate.open()
        try await first.value
        secondGate.open()
        try await second.value
    }

    @Test("[LD-PR-04] 範囲外・非有限の報告値の扱い")
    func LD_PR_04_outOfRangeAndNonFiniteReports() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start(message: "読み込み中") { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })

        reporter.report(1.4)
        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "読み込み中\n100%" })

        reporter.report(-0.5)
        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "読み込み中\n0%" })

        // 非有限値は報告そのものを無視するので、直前の表示が保たれる。
        // 受理は UI スレッドへ移して行われるため、届く可能性のある猶予を与えてから観察する。
        reporter.report(Double.nan)
        reporter.report(Double.infinity)
        _ = await DialogTestWaiting.waitUntil(timeout: .milliseconds(200)) {
            harness.builtinText != "読み込み中\n0%"
        }
        #expect(harness.builtinText == "読み込み中\n0%")

        gate.open()
        try await scope.value
    }

    @Test("[LD-PR-05] 進捗受け口を実装した VM のカスタム View に進捗が転送される")
    func LD_PR_05_progressIsForwardedToReceivingViewModel() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        harness.registry.register(ProgressReceivingLoadingTestViewModel.self) { _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }
        let viewModel = ProgressReceivingLoadingTestViewModel()
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start(viewModel) { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })

        reporter.report(0.25)
        try #require(await DialogTestWaiting.waitUntil { viewModel.receivedProgress == [0.25] })

        // 転送されるのはクランプ後の値で、非有限値は転送されない。
        reporter.report(2)
        try #require(await DialogTestWaiting.waitUntil { viewModel.receivedProgress == [0.25, 1] })
        reporter.report(Double.nan)
        _ = await DialogTestWaiting.waitUntil(timeout: .milliseconds(200)) {
            viewModel.receivedProgress.count > 2
        }
        #expect(viewModel.receivedProgress == [0.25, 1])

        gate.open()
        try await scope.value
    }

    @Test("[LD-PR-06] 受け口未実装の VM では転送されない")
    func LD_PR_06_progressIsNotForwardedWithoutReceiver() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        harness.registry.register(LoadingTestViewModel.self) { _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start(LoadingTestViewModel()) { report in
                await MainActor.run { reporter.capture(report) }
                report(0.4)
                try await gate.wait()
                return "完了"
            }
        }
        try #require(await harness.waitUntilPresenting())
        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })

        reporter.report(0.8)
        _ = await DialogTestWaiting.waitUntil(timeout: .milliseconds(200)) {
            harness.isPresenting == false
        }
        #expect(harness.isPresenting, "報告は誤りにならず、表示も処理も続く")

        gate.open()
        #expect(try await scope.value == "完了")
    }

    /// LD-PR-05 の転送を、報告と終了の順序が競る形で押さえ直す。
    @Test("報告の直後に処理が戻っても最終進捗が終了に追い越されない")
    func finalReportIsAcceptedBeforeScopeEnds() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        harness.registry.register(ProgressReceivingLoadingTestViewModel.self) { _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }

        // 受理の直列化が崩れると間欠的にしか壊れないため、繰り返して安定を見る。
        for attempt in 1...12 {
            let viewModel = ProgressReceivingLoadingTestViewModel()

            try await harness.loading.start(viewModel) { report in
                report(0.5)
                report(1)
            }

            #expect(
                viewModel.receivedProgress == [0.5, 1],
                "\(attempt) 回目: 発行済みの報告は受理順のまま、終了より先に受け口へ届く"
            )
        }
    }
}
#endif
