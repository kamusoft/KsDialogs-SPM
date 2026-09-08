#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// KMP 共有コードの ViewModel を扱う Toast の入口 (型付き登録面と ObjC 互換面) を確かめる。
///
/// 共有コードからの呼び出しそのものは Kotlin 側のテストが担うため、ここでは
/// 「互換面が受けた表示が状態の正へ届くか」と「型付き登録した中身が共有 VM で解決されるか」を見る。
@Suite("KMP 面の Toast", .serialized)
@MainActor
struct KsToastKmpTests {
    private static let contentSize = CGSize(width: 200, height: 48)

    /// 観察の途中で期限が来ないだけの長さ。
    private static let longDuration = 5000

    /// 共有コードの ViewModel の代わりに使う、Toast の契約に準拠しない素のクラス。
    final class SharedToastViewModel {
        init() {}
    }

    @Test("[TS-KM-02] 型付き登録した中身が互換面からの共有 VM で解決される")
    func TS_KM_02_customToastForSharedViewModel() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let bridge = KsDialogsInteropToastBridge(coordinator: harness.coordinator)
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        harness.toast.kmp.register(SharedToastViewModel.self) { _ in contentView }

        let failure = bridge.show(
            viewModel: SharedToastViewModel(),
            duration: NSNumber(value: Self.longDuration),
            placement: nil
        )

        #expect(failure == nil, "登録済みの共有 VM の型は受理されます")
        try #require(await harness.waitUntilPresenting())
        #expect(harness.contentViews.first === contentView, "登録した中身が共有 VM の型で解決されます")
    }

    @Test("[TS-KM-02] 未登録の共有 VM の型は受理そのものが失敗する")
    func TS_KM_02_unregisteredSharedViewModelIsRejected() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let bridge = KsDialogsInteropToastBridge(coordinator: harness.coordinator)

        let failure = bridge.show(viewModel: SharedToastViewModel(), duration: nil, placement: nil)

        #expect(failure != nil, "未登録の型では受理できません")
        await harness.drainAcceptance()
        #expect(harness.displayCount == 0, "受理に失敗した表示はリストに残りません")
    }

    @Test("互換面のメッセージ表示はデフォルト View で状態の正へ届く")
    func builtinToastThroughInteropBridge() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let bridge = KsDialogsInteropToastBridge(coordinator: harness.coordinator)

        bridge.show(
            message: "保存しました",
            duration: NSNumber(value: Self.longDuration),
            placement: nil
        )

        try #require(await harness.waitUntilPresenting())
        let contentView = try #require(harness.defaultContentViews.first)
        #expect(contentView.displayedText == "保存しました")
    }

    @Test("KMP 面の登録は Native の入口と同じレジストリに載る")
    func kmpRegistrationSharesNativeRegistry() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let contentView = FixedContentSizeView(contentSize: Self.contentSize)
        harness.toast.kmp.register(SharedToastViewModel.self) { _ in contentView }

        try harness.toast.kmp.show(SharedToastViewModel(), duration: Self.longDuration)

        try #require(await harness.waitUntilPresenting())
        #expect(harness.contentViews.first === contentView)
        #expect(
            harness.registry.factory(forKey: DialogViewModelKey(SharedToastViewModel.self)) != nil,
            "型付き登録は Native の入口が読むレジストリへ載ります"
        )
    }
}
#endif
