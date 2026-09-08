#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Toast の支援技術への通知の契約を確かめる。
///
/// デフォルト View は表示時にメッセージを読み上げへ流すが、フォーカスは移動させない。
/// フォーカスを動かす通知 (screenChanged / layoutChanged) を発行しないことがその保証になる。
/// カスタム View の読み上げは View を供給するアプリの責務なので、器は何も通知しない。
@Suite("Toast の支援技術への通知", .serialized)
@MainActor
struct ToastAccessibilityTests {
    @Test("[TS-AC-01] デフォルト View はメッセージを announce しフォーカスを奪わない")
    func TS_AC_01_defaultViewAnnouncesWithoutMovingFocus() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        harness.toast.show(message: "保存しました", duration: 5000)
        try #require(await harness.waitUntilPresenting())

        try #require(
            await DialogTestWaiting.waitUntil { harness.announcer.announcedMessages.count == 1 },
            "メッセージの announce イベントが発行される"
        )
        #expect(harness.announcer.announcedMessages == ["保存しました"])
        #expect(harness.announcer.didMoveFocus == false, "フォーカスを動かす通知は発行されない")

        let contentView = try #require(harness.defaultContentViews.first)
        #expect(
            contentView.accessibilityElementsHidden,
            "表示中の Toast は支援技術の走査対象にならず、フォーカスを奪わない"
        )
    }

    @Test("[TS-AC-01] カスタム View では器が通知もフォーカス移動もしない")
    func TS_AC_01_customViewIsLeftToTheApplication() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        try harness.toast.show(ToastTestViewModel(), duration: 5000) { _ in
            FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
        }
        try #require(await harness.waitUntilPresenting())

        #expect(harness.announcer.posts.isEmpty, "器は読み上げへ何も流さない")
    }
}
#endif
