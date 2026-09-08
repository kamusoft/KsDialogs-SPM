#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("提示前のサイズ確定", .serialized)
@MainActor
struct DialogPresentationSizingTests {
    @Test("初期状態で伸びた内容が提示の時点で高さに反映されている")
    func grownContentIsSizedBeforePresentation() async throws {
        let shortFrame = try await presentAndCaptureContentFrame(message: "短い本文")
        let longFrame = try await presentAndCaptureContentFrame(
            message: String(repeating: "折り返して縦に伸びる本文。", count: 20)
        )

        #expect(shortFrame.height > 0, "提示の時点で高さが確定していること")
        #expect(
            longFrame.height > shortFrame.height,
            "初期状態を反映した内容の高さで提示されること (短い \(shortFrame.height) / 長い \(longFrame.height))"
        )
    }

    @Test("添付した比率サイズが提示の時点で反映されている")
    func attachedProportionalSizeIsAppliedAtPresentation() async throws {
        let harness = DialogTestHarness()
        harness.registry.register(BasicTestDialogViewModel.self) { _, _ in
            let contentView = DialogTestContentView()
            contentView.ksDialogOptions = DialogOptions(
                layoutArea: .window,
                dialogMargin: .zero,
                proportionalWidth: 0.5,
                proportionalHeight: 0.25
            )
            return contentView
        }

        let showTask = Task {
            try await harness.dialogs.show(BasicTestDialogViewModel(message: "比率サイズ"))
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let frame = try #require(harness.presentationSurface.contentFramesAtPresentation.first)
        harness.topmostContainer?.reportOutsideTap()
        _ = try? await showTask.value

        let bounds = harness.presentationSurface.presentationBounds
        let tolerance = DialogLayoutCaseLoader.table.tolerance
        #expect(abs(Double(frame.width - bounds.width * 0.5)) <= tolerance, "実測 \(frame)")
        #expect(abs(Double(frame.height - bounds.height * 0.25)) <= tolerance, "実測 \(frame)")
    }

    /// メッセージを表示するダイアログを1枚出し、present が呼ばれた時点の中身の矩形を返す。
    private func presentAndCaptureContentFrame(message: String) async throws -> CGRect {
        let harness = DialogTestHarness()
        harness.registry.register(BasicTestDialogViewModel.self) { viewModel, _ in
            MessageTestContentView(message: viewModel.message)
        }

        let showTask = Task {
            try await harness.dialogs.show(BasicTestDialogViewModel(message: message))
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let frame = try #require(harness.presentationSurface.contentFramesAtPresentation.first)
        harness.topmostContainer?.reportOutsideTap()
        _ = try? await showTask.value
        return frame
    }
}
#endif
