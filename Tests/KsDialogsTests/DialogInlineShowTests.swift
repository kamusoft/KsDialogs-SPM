#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

@Suite("インライン show", .serialized)
@MainActor
struct DialogInlineShowTests {
    private static let contentSize = CGSize(width: 240, height: 120)

    @Test("SwiftUI の中身をインラインで表示して型付き結果を受け取る")
    func swiftUIContentIsShownInline() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()

        let showTask = Task { () -> DialogResult<Bool> in
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "インライン")) { viewModel, notifier in
                recorder.recording(
                    notifier: notifier,
                    content: Text(viewModel.message)
                        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
                )
            }
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        #expect(container.contentHost != nil, "SwiftUI のインライン表示もホストを伴うこと")

        try await recorder.notifier(at: 0).complete(true)

        #expect(try await showTask.value == .completed(true))
        #expect(await DialogTestWaiting.waitUntil { harness.presentedContainers.isEmpty })
    }

    @Test("UIView の中身をインラインで表示して型付き結果を受け取る")
    func uiViewContentIsShownInline() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()

        let showTask = Task { () -> DialogResult<Bool> in
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "インライン")) { _, notifier in
                let view = DialogTestContentView()
                recorder.record(view: view, notifier: notifier)
                return view
            }
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try await recorder.notifier(at: 0).complete(true)

        #expect(try await showTask.value == .completed(true))
    }

    @Test("インライン show は既存の登録を使わず、登録内容も変えない")
    func inlineShowNeitherUsesNorChangesRegistration() async throws {
        let harness = DialogTestHarness()
        harness.registry.register(BasicTestDialogViewModel.self) { _, _ in
            FixedContentSizeView(contentSize: Self.contentSize)
        }
        let inlineRecorder = DialogTestRecorder<Bool>()

        let inlineTask = Task {
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "インライン")) { _, notifier in
                let view = DialogTestContentView()
                inlineRecorder.record(view: view, notifier: notifier)
                return view
            }
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        // 登録済みの factory ではなく、渡した factory の中身が出ている。
        #expect(harness.topmostContainer?.contentView is DialogTestContentView)
        try await inlineRecorder.notifier(at: 0).cancel()
        _ = try? await inlineTask.value
        #expect(await DialogTestWaiting.waitUntil { harness.presentedContainers.isEmpty })

        // 登録はインライン show の前後で変わらない。
        let registeredTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "登録")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        #expect(harness.topmostContainer?.contentView is FixedContentSizeView)
        harness.topmostContainer?.reportOutsideTap()
        _ = try? await registeredTask.value
    }

    @Test("インライン show はその ViewModel 型を登録済みにしない")
    func inlineShowDoesNotRegisterViewModelType() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()

        let inlineTask = Task {
            try await harness.dialogs.show(UnregisteredTestDialogViewModel()) { _, notifier in
                let view = DialogTestContentView()
                recorder.record(view: view, notifier: notifier)
                return view
            }
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try await recorder.notifier(at: 0).cancel()
        _ = try? await inlineTask.value

        // レジストリ経由の show は依然として未登録で失敗する。
        await #expect(throws: DialogError.viewFactoryNotRegistered(
            viewModelType: String(describing: UnregisteredTestDialogViewModel.self)
        )) {
            _ = try await harness.dialogs.show(UnregisteredTestDialogViewModel())
        }
    }

    @Test("同じ型の並行インライン show は互いに独立する")
    func concurrentInlineShowsOfSameTypeAreIndependent() async throws {
        let harness = DialogTestHarness()
        let firstRecorder = DialogTestRecorder<Bool>()
        let secondRecorder = DialogTestRecorder<Bool>()

        let firstTask = Task {
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "1枚目")) { _, notifier in
                let view = FixedContentSizeView(contentSize: Self.contentSize)
                firstRecorder.record(view: view, notifier: notifier)
                return view
            }
        }
        try #require(await harness.waitForPresentedContainers(count: 1))

        let secondTask = Task {
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "2枚目")) { _, notifier in
                let view = DialogTestContentView()
                secondRecorder.record(view: view, notifier: notifier)
                return view
            }
        }
        try #require(await harness.waitForPresentedContainers(count: 2))

        // それぞれの factory が独立に呼ばれ、別々の中身が出ている。
        #expect(harness.presentedContainers.first?.contentView is FixedContentSizeView)
        #expect(harness.topmostContainer?.contentView is DialogTestContentView)

        // 手前の1枚だけを閉じても、もう片方は表示されたまま未確定である。
        try await secondRecorder.notifier(at: 0).complete(true)
        #expect(try await secondTask.value == .completed(true))
        #expect(await DialogTestWaiting.waitUntil { harness.presentedContainers.count == 1 })
        #expect(firstTask.isCancelled == false)

        try await firstRecorder.notifier(at: 0).complete(false)
        #expect(try await firstTask.value == .completed(false))
    }

    @Test("インライン show の placement は添付をまるごと置換する")
    func inlineShowPlacementReplacesAttachment() async throws {
        let screen = DialogLayoutCase.Size(w: 400, h: 800)
        let harness = DialogTestHarness()
        harness.presentationSurface.presentationBounds = CGRect(x: 0, y: 0, width: screen.w, height: screen.h)
        let recorder = DialogTestRecorder<Bool>()

        let showTask = Task {
            try await harness.dialogs.show(
                BasicTestDialogViewModel(message: "配置"),
                placement: DialogPlacement(horizontalAlignment: .start, verticalAlignment: .start)
            ) { _, notifier in
                let view = FixedContentSizeView(contentSize: Self.contentSize)
                view.ksDialogOptions = DialogOptions(layoutArea: .window, dialogMargin: .zero)
                view.ksDialogPlacement = DialogPlacement(horizontalAlignment: .end, verticalAlignment: .end)
                recorder.record(view: view, notifier: notifier)
                return view
            }
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let frame = try #require(harness.presentationSurface.contentFramesAtPresentation.first)
        try await recorder.notifier(at: 0).cancel()
        _ = try? await showTask.value

        // 採用されるのは show 引数の Start / Start。
        DialogRectExpectation.expect(
            frame,
            equals: CGRect(origin: .zero, size: Self.contentSize)
        )
    }
}
#endif
