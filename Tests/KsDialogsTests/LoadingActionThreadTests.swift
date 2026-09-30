#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// スコープ形の処理が始まるスレッドを確かめる。
///
/// 処理の型は MainActor 隔離なので、その場で書いたクロージャは呼び出し元のスレッドによらず
/// UI スレッドで始まる。`@concurrent` を付けたクロージャは、呼び出し元によらず UI スレッド外で始まる。
/// どちらも処理の最初の文で実行スレッドを読み取り、その値を処理の戻り値として持ち帰って判定する。
@Suite("スコープ形の処理が始まるスレッド", .serialized)
@MainActor
struct LoadingActionThreadTests {
    private static let contentSize = CGSize(width: 120, height: 80)

    /// 呼び出し元のスレッドと、処理の最初の文を実行したスレッドの組。
    private struct StartObservation: Sendable {
        let calledOnMainThread: Bool
        let startedOnMainThread: Bool
    }

    // MARK: - 既定ローディング

    @Test("[LD-TH-01] 既定では、UI スレッドから呼んでも UI スレッドで始まる")
    func LD_TH_01_defaultStartsOnMainThreadWhenCalledFromMainThread() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        let calledOnMainThread = DialogTestThread.isMainThread()
        let startedOnMainThread = try await harness.loading.start(message: "読み込み中") { _ in
            DialogTestThread.isMainThread()
        }

        #expect(calledOnMainThread, "呼び出しは UI スレッドから行っている")
        #expect(startedOnMainThread, "処理は UI スレッドで始まる")
    }

    @Test("[LD-TH-02] 既定では、UI スレッド外から呼んでも UI スレッドで始まる")
    func LD_TH_02_defaultStartsOnMainThreadWhenCalledOffMainThread() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let loading = harness.loading

        let observation = try await Task.detached { () -> StartObservation in
            let calledOnMainThread = DialogTestThread.isMainThread()
            let startedOnMainThread = try await loading.start(message: "読み込み中") { _ in
                DialogTestThread.isMainThread()
            }
            return StartObservation(
                calledOnMainThread: calledOnMainThread,
                startedOnMainThread: startedOnMainThread
            )
        }.value

        #expect(observation.calledOnMainThread == false, "呼び出しは UI スレッド外から行っている")
        #expect(observation.startedOnMainThread, "処理は UI スレッドで始まる")
    }

    @Test("[LD-TH-03] UI スレッド外の指定では、UI スレッドから呼んでも UI スレッド外で始まる")
    func LD_TH_03_concurrentStartsOffMainThreadWhenCalledFromMainThread() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        let calledOnMainThread = DialogTestThread.isMainThread()
        let startedOnMainThread = try await harness.loading.start(message: "読み込み中") { @concurrent _ in
            DialogTestThread.isMainThread()
        }

        #expect(calledOnMainThread, "呼び出しは UI スレッドから行っている")
        #expect(startedOnMainThread == false, "処理は UI スレッド外で始まる")
    }

    @Test("[LD-TH-04] UI スレッド外の指定では、UI スレッド外から呼んでも UI スレッド外で始まる")
    func LD_TH_04_concurrentStartsOffMainThreadWhenCalledOffMainThread() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let loading = harness.loading

        let observation = try await Task.detached { () -> StartObservation in
            let calledOnMainThread = DialogTestThread.isMainThread()
            let startedOnMainThread = try await loading.start(message: "読み込み中") { @concurrent _ in
                DialogTestThread.isMainThread()
            }
            return StartObservation(
                calledOnMainThread: calledOnMainThread,
                startedOnMainThread: startedOnMainThread
            )
        }.value

        #expect(observation.calledOnMainThread == false, "呼び出しは UI スレッド外から行っている")
        #expect(observation.startedOnMainThread == false, "処理は UI スレッド外で始まる")
    }

    // MARK: - カスタム View の入口

    @Test("[LD-TH-05] カスタム View の入口でも、既定は UI スレッドで始まる")
    func LD_TH_05_customEntriesStartOnMainThreadByDefault() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        Self.registerCustomViewModels(in: harness)
        let loading = harness.loading

        let (calledOnMainThread, starts) = try await Task.detached { () -> (Bool, [String: Bool]) in
            let calledOnMainThread = DialogTestThread.isMainThread()
            let starts = try await Self.startCustomEntriesByDefault(loading: loading)
            return (calledOnMainThread, starts)
        }.value

        #expect(calledOnMainThread == false, "呼び出しは UI スレッド外から行っている")
        #expect(starts.count == 4, "4 つの入口をすべて通っている")
        for (entry, startedOnMainThread) in starts.sorted(by: { $0.key < $1.key }) {
            #expect(startedOnMainThread, "\(entry): 処理は UI スレッドで始まる")
        }
    }

    @Test("[LD-TH-06] カスタム View の入口でも、UI スレッド外の指定が効く")
    func LD_TH_06_customEntriesStartOffMainThreadWhenConcurrent() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        Self.registerCustomViewModels(in: harness)
        let loading = harness.loading

        let calledOnMainThread = DialogTestThread.isMainThread()
        var starts: [String: Bool] = [:]
        starts["インスタンス渡し"] = try await loading.start(LoadingTestViewModel()) { @concurrent _ in
            DialogTestThread.isMainThread()
        }
        starts["インライン (UIKit)"] = try await loading.start(
            LoadingTestViewModel(),
            factory: { _ in FixedContentSizeView(contentSize: Self.contentSize) }
        ) { @concurrent _ in
            DialogTestThread.isMainThread()
        }
        starts["インライン (SwiftUI)"] = try await loading.start(
            LoadingTestViewModel(),
            factory: { _ in Color.clear.frame(width: 120, height: 80) }
        ) { @concurrent _ in
            DialogTestThread.isMainThread()
        }
        starts["型指定"] = try await loading.start(ConfigurableLoadingTestViewModel.self) { @concurrent _ in
            DialogTestThread.isMainThread()
        }

        #expect(calledOnMainThread, "呼び出しは UI スレッドから行っている")
        #expect(starts.count == 4, "4 つの入口をすべて通っている")
        for (entry, startedOnMainThread) in starts.sorted(by: { $0.key < $1.key }) {
            #expect(startedOnMainThread == false, "\(entry): 処理は UI スレッド外で始まる")
        }
    }

    // MARK: - 既存の契約との両立

    @Test("[LD-TH-07] UI スレッド外で始まった action からの進捗報告が届く")
    func LD_TH_07_progressFromConcurrentActionIsDeliveredInOrder() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        harness.registry.register(ProgressReceivingLoadingTestViewModel.self) { _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }

        // 報告と終了の順序は間欠的にしか崩れないため、繰り返して安定を見る。
        for attempt in 1...8 {
            let viewModel = ProgressReceivingLoadingTestViewModel()

            let startedOnMainThread = try await harness.loading.start(viewModel) { @concurrent report in
                let startedOnMainThread = DialogTestThread.isMainThread()
                report(0.25)
                report(0.5)
                report(1)
                return startedOnMainThread
            }

            #expect(startedOnMainThread == false, "\(attempt) 回目: 処理は UI スレッド外で始まっている")
            #expect(
                viewModel.receivedProgress == [0.25, 0.5, 1],
                "\(attempt) 回目: 報告は報告した順に届き、最後の報告が終了に追い越されない"
            )
        }
    }

    @Test("[LD-TH-08] どちらの指定でも、action の失敗は伝播して表示が閉じる")
    func LD_TH_08_failurePropagatesAndLoadingClosesForBothThreads() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        await #expect(throws: LoadingTestScopeError.failed) {
            try await harness.loading.start(message: "読み込み中") { _ in
                throw LoadingTestScopeError.failed
            }
        }
        #expect(harness.coordinator.coalescedUseCount == 0, "既定: 合流1件の終了として数えられる")
        #expect(harness.isPresenting == false, "既定: Loading は閉じる")

        await #expect(throws: LoadingTestScopeError.failed) {
            try await harness.loading.start(message: "読み込み中") { @concurrent _ in
                throw LoadingTestScopeError.failed
            }
        }
        #expect(harness.coordinator.coalescedUseCount == 0, "UI スレッド外: 合流1件の終了として数えられる")
        #expect(harness.isPresenting == false, "UI スレッド外: Loading は閉じる")
    }

    // MARK: - 関数を名前で渡す場合

    @Test("[LD-HI-02] isolation の指定が無い関数を名前で渡すと UI スレッド外で始まる")
    func LD_HI_02_namedNonisolatedFunctionStartsOffMainThread() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        let calledOnMainThread = DialogTestThread.isMainThread()
        let startedOnMainThread = try await harness.loading.start(
            loadingActionThreadTestReportsStartThread
        )

        #expect(calledOnMainThread, "呼び出しは UI スレッドから行っている")
        #expect(startedOnMainThread == false, "関数自身の isolation が優先され、UI スレッド外で始まる")
    }

    // MARK: - 補助

    /// カスタム View の 4 つの入口が使う登録を済ませる。
    private static func registerCustomViewModels(in harness: LoadingTestHarness) {
        harness.registry.register(LoadingTestViewModel.self) { _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }
        harness.registry.register(ConfigurableLoadingTestViewModel.self) {
            ConfigurableLoadingTestViewModel()
        }
        harness.registry.register(ConfigurableLoadingTestViewModel.self) { _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }
    }

    /// カスタム View の 4 つの入口を、スレッドの指定なしのクロージャで順に開始する。
    /// 呼び出し元のスレッドを変えないよう、UI スレッドに隔離しない。
    nonisolated private static func startCustomEntriesByDefault(loading: Loading) async throws -> [String: Bool] {
        var starts: [String: Bool] = [:]
        starts["インスタンス渡し"] = try await loading.start(LoadingTestViewModel()) { _ in
            DialogTestThread.isMainThread()
        }
        starts["インライン (UIKit)"] = try await loading.start(
            LoadingTestViewModel(),
            factory: { _ in FixedContentSizeView(contentSize: CGSize(width: 120, height: 80)) }
        ) { _ in
            DialogTestThread.isMainThread()
        }
        starts["インライン (SwiftUI)"] = try await loading.start(
            LoadingTestViewModel(),
            factory: { _ in Color.clear.frame(width: 120, height: 80) }
        ) { _ in
            DialogTestThread.isMainThread()
        }
        starts["型指定"] = try await loading.start(ConfigurableLoadingTestViewModel.self) { _ in
            DialogTestThread.isMainThread()
        }
        return starts
    }
}

/// isolation の指定が無い async 関数。最初の文で実行スレッドを読み取って返す。
///
/// このテストターゲットは、isolation の指定が無い async 関数を呼び出し元の actor から離して実行する
/// 言語設定 (Swift 6 の既定。`NonisolatedNonsendingByDefault` は有効にしていない) でビルドされる。
/// そのため、この関数を名前で渡すと、処理の型の MainActor 隔離ではなく関数自身の性質が優先される。
private func loadingActionThreadTestReportsStartThread(
    _ report: @escaping @Sendable (Double) -> Void
) async throws -> Bool {
    DialogTestThread.isMainThread()
}
#endif
