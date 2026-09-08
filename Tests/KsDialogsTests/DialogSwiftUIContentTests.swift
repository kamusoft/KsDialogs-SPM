#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

@Suite("SwiftUI の中身の登録と表示", .serialized)
@MainActor
struct DialogSwiftUIContentTests {
    private static let contentSize = CGSize(width: 240, height: 120)

    /// ダイアログが閉じる経路。ホストの解放はどれを通っても同じでなければならない。
    enum CloseRoute: String, CaseIterable, CustomStringConvertible {
        /// 中身が結果つきで完了を報告した。
        case completed
        /// 中身がキャンセルを報告した。
        case cancelled
        /// show を待っている呼び出し元が待機を打ち切った。
        case callerCancelled

        var description: String { rawValue }
    }

    @Test("SwiftUI の中身を登録して表示し、型付き結果を受け取る")
    func swiftUIContentIsRegisteredAndReturnsTypedResult() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { viewModel, notifier in
            recorder.recording(
                notifier: notifier,
                content: Text(viewModel.message)
                    .frame(width: Self.contentSize.width, height: Self.contentSize.height)
            )
        }

        let showTask = Task { () -> DialogResult<Bool> in
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "SwiftUI の中身"))
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        // 中身の完了操作にあたる報告。SwiftUI から渡された結果報告口は真偽値に型付いている。
        let notifier = try await recorder.notifier(at: 0)
        notifier.complete(true)

        #expect(try await showTask.value == .completed(true))
        #expect(await DialogTestWaiting.waitUntil { harness.presentedContainers.isEmpty })
    }

    @Test("SwiftUI の中身はホストごと器に組み込まれる")
    func swiftUIContentIsHostedInsideContainer() async throws {
        let harness = DialogTestHarness()
        harness.registry.register(BasicTestDialogViewModel.self) { _, _ in
            FixedSizeSwiftUIContent(contentSize: Self.contentSize)
        }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "ホスト")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        let host = try #require(container.contentHost, "SwiftUI の中身はホストを伴うこと")

        #expect(host.parent === container, "ホストが器の child として組み込まれていること")
        #expect(host.view.isDescendant(of: container.contentView), "ホストの View が中身の中に載っていること")
        #expect(container.didExhaustAttributeSupplyWait == false, "添付値の到達待ちで提示が繰り下がらないこと")

        // ホストが要求するサイズが内容サイズとして働き、提示の時点で確定している (core/ADR-0008)。
        let frameAtPresentation = try #require(harness.presentationSurface.contentFramesAtPresentation.first)
        DialogRectExpectation.expect(
            CGRect(origin: .zero, size: frameAtPresentation.size),
            equals: CGRect(origin: .zero, size: Self.contentSize),
            "提示の時点で内容サイズが確定していること"
        )

        showTask.cancel()
        _ = try? await showTask.value
    }

    @Test("全閉鎖経路でホストが解放される", arguments: CloseRoute.allCases)
    func hostIsReleasedOnEveryCloseRoute(route: CloseRoute) async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            recorder.recording(
                notifier: notifier,
                content: FixedSizeSwiftUIContent(contentSize: Self.contentSize)
            )
        }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "解放")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        weak var releasedHost = try #require(container.contentHost)

        switch route {
        case .completed:
            try await recorder.notifier(at: 0).complete(true)
        case .cancelled:
            try await recorder.notifier(at: 0).cancel()
        case .callerCancelled:
            showTask.cancel()
        }
        _ = try? await showTask.value

        let detached = await DialogTestWaiting.waitUntil { container.contentHost == nil }
        #expect(detached, "\(route): ホストが器の child から外れること")
        let released = await DialogTestWaiting.waitUntil { releasedHost == nil }
        #expect(released, "\(route): ホストが解放されること")
    }

    @Test("器が破棄されるとホストも一緒に解放される")
    func hostIsReleasedWithContainer() async throws {
        weak var releasedHost: UIViewController?
        weak var releasedContainer: DialogContainerViewController?

        // 器への強い参照をこのスコープに閉じ込め、抜けた時点で解放されるようにする。
        do {
            let content = DialogSwiftUIHost.makeContent(
                FixedSizeSwiftUIContent(contentSize: Self.contentSize)
            )
            let container = DialogContainerViewController(
                content: content,
                resultChannel: DialogResultChannel()
            )
            container.loadViewIfNeeded()
            releasedHost = container.contentHost
            releasedContainer = container
            #expect(releasedHost != nil)
        }

        #expect(await DialogTestWaiting.waitUntil { releasedContainer == nil }, "器が解放されること")
        #expect(await DialogTestWaiting.waitUntil { releasedHost == nil }, "ホストも一緒に解放されること")
    }
}
#endif
