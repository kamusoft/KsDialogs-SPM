#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// KMP 共有コードの ViewModel を扱う Loading の入口 (型付き登録面と ObjC 互換面) を確かめる。
///
/// 共有コードからの呼び出しそのものは Kotlin 側のテストが担うため、ここでは
/// 「互換面が受けた操作が状態の正へ届くか」と「型付き登録した中身が共有 VM で解決されるか」を見る。
@Suite("KMP 面の Loading", .serialized)
@MainActor
struct KsLoadingKmpTests {
    private static let contentSize = CGSize(width: 120, height: 80)

    /// 共有コードの ViewModel の代わりに使う、Loading の契約に準拠しない素のクラス。
    final class SharedLoadingViewModel {
        init() {}
    }

    @Test("[LD-KM-01] 互換面の開始・進捗・終了が既定ローディングの表示に届く")
    func LD_KM_01_builtinLoadingThroughInteropBridge() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let bridge = KsDialogsInteropLoadingBridge(coordinator: harness.coordinator)

        let handle = try #require(await beginBuiltin(bridge, message: "読み込み中"))
        try #require(await harness.waitUntilPresenting())

        bridge.report(progress: 0.25, handle: handle)
        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "読み込み中\n25%" })

        await endUse(bridge, handle)

        #expect(harness.isPresenting == false, "合流最後の1件の終了で表示が閉じます")
    }

    @Test("[LD-KM-03] KMP 面で登録したカスタム Loading が共有 VM で表示され進捗が転送される")
    func LD_KM_03_customLoadingForSharedViewModel() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let bridge = KsDialogsInteropLoadingBridge(coordinator: harness.coordinator)
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        harness.loading.kmp.register(SharedLoadingViewModel.self) { _ in contentView }
        let receiver = LoadingTestProgressRecorder()

        let handle = try #require(
            await begin(bridge, viewModel: SharedLoadingViewModel(), progress: { receiver.record($0) })
        )
        try #require(await harness.waitUntilPresenting())

        #expect(harness.contentView === contentView, "登録した中身が共有 VM の型で解決されます")

        bridge.report(progress: 1.5, handle: handle)
        try #require(await DialogTestWaiting.waitUntil { receiver.values == [1.0] })

        await endUse(bridge, handle)
    }

    @Test("未登録の共有 VM の型は構成ミスとして開始に失敗する")
    func unregisteredSharedViewModelFailsToBegin() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let bridge = KsDialogsInteropLoadingBridge(coordinator: harness.coordinator)

        let failure = await withCheckedContinuation { (continuation: CheckedContinuation<NSError?, Never>) in
            bridge.begin(viewModel: SharedLoadingViewModel(), placement: nil, progress: nil) { _, error in
                continuation.resume(returning: error)
            }
        }

        #expect(failure != nil, "未登録の型では開始できません")
        #expect(harness.isPresenting == false)
    }

    /// LD-KM-03 の転送を、報告と終了の順序が競る形で押さえ直す。
    /// 共有コードは報告と終了を別々の呼び出しで行うため、この2つの受理順が保証されないと最終報告が落ちる。
    @Test("互換面で報告の直後に終了しても最終進捗が追い越されない")
    func finalReportIsAcceptedBeforeEndUse() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let bridge = KsDialogsInteropLoadingBridge(coordinator: harness.coordinator)
        harness.loading.kmp.register(SharedLoadingViewModel.self) { _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }

        // 受理の直列化が崩れると間欠的にしか壊れないため、繰り返して安定を見る。
        for attempt in 1...12 {
            let receiver = LoadingTestProgressRecorder()
            let handle = try #require(
                await begin(bridge, viewModel: SharedLoadingViewModel(), progress: { receiver.record($0) })
            )

            bridge.report(progress: 0.5, handle: handle)
            bridge.report(progress: 1, handle: handle)
            await endUse(bridge, handle)

            #expect(receiver.values == [0.5, 1], "\(attempt) 回目: 報告は受理順のまま、終了より先に転送先へ届く")
        }
    }

    /// 既定ローディングの合流1件を開始し、そのハンドルを受け取る。
    private func beginBuiltin(
        _ bridge: KsDialogsInteropLoadingBridge,
        message: String?
    ) async -> KsDialogsInteropLoadingUseHandle? {
        await withCheckedContinuation { continuation in
            bridge.beginBuiltin(message: message, placement: nil) { handle, _ in
                continuation.resume(returning: handle)
            }
        }
    }

    /// カスタム Loading の合流1件を開始し、そのハンドルを受け取る。
    private func begin(
        _ bridge: KsDialogsInteropLoadingBridge,
        viewModel: Any,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> KsDialogsInteropLoadingUseHandle? {
        await withCheckedContinuation { continuation in
            bridge.begin(viewModel: viewModel, placement: nil, progress: progress) { handle, _ in
                continuation.resume(returning: handle)
            }
        }
    }

    /// 合流1件を終了し、器の撤去まで待つ。
    private func endUse(
        _ bridge: KsDialogsInteropLoadingBridge,
        _ handle: KsDialogsInteropLoadingUseHandle
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            bridge.endUse(handle) { continuation.resume() }
        }
    }
}

/// 互換面へ渡した報告先が受け取った進捗を順に書き留める。任意のスレッドから呼ばれる。
final class LoadingTestProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Double] = []

    /// 受け取った進捗を呼ばれた順に並べたもの。
    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func record(_ progress: Double) {
        lock.lock()
        defer { lock.unlock() }
        storedValues.append(progress)
    }
}
#endif
