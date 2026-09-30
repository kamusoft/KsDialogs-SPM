#if canImport(UIKit)
import Testing

/// 各テストの本体を始める前に、MainActor に積まれた仕事がはけるのを待つ trait。
///
/// 実時間の期限を持つ表示 (Toast の duration) を観察するスイートに付ける。
/// 並列実行の立ち上がりでは多数のスイートが一斉に MainActor へ仕事を積むため、
/// 表示の受理が MainActor で走るまでに期限 (数百ミリ秒) を超える遅れが出て、
/// 表示が取り付く前に満了して捨てられることがある。待ちの長さは
/// `DialogTestWaiting.awaitMainActorResponsive` が決める。
struct MainActorResponsiveTrait: TestTrait, SuiteTrait, TestScoping {
    /// スイートに付けたとき、含まれる各テストにも効かせる。
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        // スイート自体の範囲 (testCase が無い) では待たず、各テストケースの直前でだけ待つ。
        if testCase != nil {
            await DialogTestWaiting.awaitMainActorResponsive()
        }
        try await function()
    }
}

extension Trait where Self == MainActorResponsiveTrait {
    /// テストの本体を始める前に、MainActor に積まれた仕事がはけるのを待つ。
    static var awaitsMainActorResponsive: Self { Self() }
}
#endif
