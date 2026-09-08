#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Toast の出入りの演出の契約 (core/ADR-0017 のフック機構) を確かめる。
///
/// カスタム Toast View には Dialog / Loading と同じ意味で `ksDialogTransition` が効き、
/// 添付を省略したカスタム View とデフォルト View は器の既定演出で出入りする。
/// Toast は結果を持たないため、結果のラッチと配送は対象外である。
@Suite("Toast の出入りの演出", .serialized)
@MainActor
struct ToastTransitionTests {
    @Test("[TS-TR-01] カスタム View の演出フックが両局面で呼ばれる")
    func TS_TR_01_customViewHooksRunInBothPhases() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let probe = DialogTransitionProbe()

        try harness.toast.show(ToastTestViewModel(), duration: 400) { _ in
            let view = FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
            view.ksDialogTransition = DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.immediateHook(.dismissal)
            )
            return view
        }

        try #require(await harness.waitUntilPresenting())
        let contentView = try #require(harness.contentViews.first)
        try #require(
            await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 },
            "入りのフックが呼ばれる"
        )
        let presentationCall = try #require(probe.firstCall(.presentation))
        #expect(presentationCall.hostView === contentView, "フックはホスト View を受け取る")
        #expect(presentationCall.isOnWindow, "呼ばれる時点で画面に載っている")

        #expect(await harness.waitUntilEmpty(), "期限の到達で撤去まで進む")
        #expect(probe.callCount(.dismissal) == 1, "出のフックが呼ばれる")
        #expect(probe.firstCall(.dismissal)?.hostView === contentView)
        #expect(contentView.window == nil, "完了通知の後に撤去される")
    }

    @Test("[TS-TR-02] デフォルト View は器の既定演出で出入りする")
    func TS_TR_02_defaultViewUsesContainerDefaultTransition() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        harness.toast.show(message: "既定の演出", duration: 400)
        try #require(await harness.waitUntilPresenting())
        let container = try #require(harness.containers.first)
        let contentView = container.contentView

        try #require(
            await DialogTestWaiting.waitUntil { container.isLayoutSnapshotFrozen },
            "実効値と同じ時点で演出が固定される"
        )
        #expect(container.resolvedTransition != nil, "器の既定演出が採用される")

        #expect(await harness.waitUntilEmpty(), "演出起因で表示が残らない")
        #expect(contentView.window == nil)
        #expect(harness.attachedContainerViews.isEmpty)
    }
}
#endif
