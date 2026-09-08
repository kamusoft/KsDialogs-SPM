#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Toast の多重表示と表示の継続の契約 (core/ADR-0030) を確かめる。
///
/// 多重起動はすべて表示され、重なり順は起動順になる。各表示は自分の duration で独立に消え、
/// 画面遷移・回転をまたいでも表示は続き、残り時間は巻き戻らない。
/// Loading と同時に出たときは起動順によらず Loading が前面である。
@Suite("Toast の多重表示と表示の継続", .serialized)
@MainActor
struct ToastMultiDisplayTests {
    /// 観察の途中で期限が来ないだけの長さ。
    private static let longDuration = 5000

    @Test("[TS-MX-01] 多重起動はすべて表示され起動順に重なる")
    func TS_MX_01_multipleShowsStackInLaunchOrder() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        harness.toast.show(message: "1枚目", duration: Self.longDuration)
        harness.toast.show(message: "2枚目", duration: Self.longDuration)
        harness.toast.show(message: "3枚目", duration: Self.longDuration)

        try #require(await harness.waitUntilPresenting(count: 3), "3枚すべてが表示される")
        #expect(
            harness.defaultContentViews.map(\.displayedText) == ["1枚目", "2枚目", "3枚目"],
            "表示リストは起動順に並ぶ"
        )

        let attached = harness.attachedContainerViews
        let containerViews = harness.containers.map(\.view)
        #expect(attached == containerViews, "取り付け先での重なり順が起動順と一致する")
        let indices = attached.compactMap { harness.window.subviews.firstIndex(of: $0) }
        #expect(indices.count == 3)
        #expect(indices == indices.sorted(), "後に起動したものほど手前に重なる")
    }

    @Test("[TS-MX-02] 各表示は自分の duration で独立に消える")
    func TS_MX_02_eachDisplayExpiresIndependently() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        harness.toast.show(message: "短い", duration: 300)
        harness.toast.show(message: "長い", duration: Self.longDuration)

        try #require(await harness.waitUntilPresenting(count: 2))
        try #require(
            await DialogTestWaiting.waitUntil { harness.displayCount == 1 },
            "短い方の期限で1枚だけ消える"
        )

        #expect(
            harness.defaultContentViews.map(\.displayedText) == ["長い"],
            "長い方は自分の duration まで残る"
        )
    }

    @Test("[TS-MX-03] ページ遷移をまたいで表示が継続する")
    func TS_MX_03_displaySurvivesPageTransition() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let navigation = UINavigationController(rootViewController: UIViewController())
        harness.window.rootViewController = navigation
        harness.window.layoutIfNeeded()

        harness.toast.show(message: "遷移をまたぐ", duration: 800)
        try #require(await harness.waitUntilPresenting())
        let contentView = try #require(harness.contentViews.first)

        // 器は取り付け先 (key window) に直接載っているため、画面の遷移に巻き込まれない。
        navigation.pushViewController(UIViewController(), animated: false)
        harness.window.layoutIfNeeded()

        #expect(harness.displayCount == 1, "遷移後も表示され続ける")
        #expect(contentView.window === harness.window)
        #expect(await harness.waitUntilEmpty(), "duration の経過で消える")
    }

    @Test("[TS-MX-04] 回転しても表示が継続し残り時間は維持される")
    func TS_MX_04_rotationKeepsDisplayAndRemainingTime() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let duration = 800

        let startedAt = ContinuousClock.now
        harness.toast.show(message: "回転しても続く", duration: duration)
        try #require(await harness.waitUntilPresenting())
        let contentView = try #require(harness.contentViews.first)

        try await Task.sleep(for: .milliseconds(200))
        harness.changeGeometry(
            screen: DialogLayoutCase.Size(w: 844, h: 390),
            insets: DialogLayoutCase.Insets(top: 0, bottom: 21, left: 59, right: 59)
        )

        #expect(harness.displayCount == 1, "回転しても表示は途切れない")
        #expect(contentView.window === harness.window)
        #expect(contentView.frame.maxX <= 844, "回転後の寸法で配置し直される")

        #expect(await harness.waitUntilEmpty())
        let elapsed = ContinuousClock.now - startedAt
        #expect(
            elapsed < .milliseconds(duration + 1500),
            "残り duration は巻き戻らない (経過 \(elapsed))"
        )
    }

    @Test("[TS-MX-05] Loading は起動順によらず Toast より前面")
    func TS_MX_05_loadingStaysInFrontOfToast() async throws {
        let loadingFirst = ToastTestHarness()
        await loadingFirst.loading.show(message: "先に Loading")
        loadingFirst.toast.show(message: "後から Toast", duration: Self.longDuration)
        try #require(await loadingFirst.waitUntilPresenting())
        #expect(
            try Self.loadingIndex(in: loadingFirst) > Self.toastIndex(in: loadingFirst),
            "Loading が先でも Loading が前面"
        )
        await loadingFirst.loading.hide()
        loadingFirst.tearDown()

        let toastFirst = ToastTestHarness()
        toastFirst.toast.show(message: "先に Toast", duration: Self.longDuration)
        try #require(await toastFirst.waitUntilPresenting())
        await toastFirst.loading.show(message: "後から Loading")
        #expect(
            try Self.loadingIndex(in: toastFirst) > Self.toastIndex(in: toastFirst),
            "Toast が先でも Loading が前面"
        )
        await toastFirst.loading.hide()
        toastFirst.tearDown()
    }

    /// 取り付け先での Loading の器の重なり位置。
    private static func loadingIndex(in harness: ToastTestHarness) throws -> Int {
        let view = try #require(harness.window.subviews.first { $0 is LoadingContainerRootView })
        return try #require(harness.window.subviews.firstIndex(of: view))
    }

    /// 取り付け先での Toast の器の重なり位置。
    private static func toastIndex(in harness: ToastTestHarness) throws -> Int {
        let view = try #require(harness.window.subviews.first { $0 is ToastContainerRootView })
        return try #require(harness.window.subviews.firstIndex(of: view))
    }
}
#endif
