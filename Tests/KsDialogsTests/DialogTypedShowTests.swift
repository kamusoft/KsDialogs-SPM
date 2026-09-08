#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

@Suite("ViewModel の型を渡す show", .serialized)
@MainActor
struct DialogTypedShowTests {
    /// configure が投げる、テスト専用の失敗。
    struct ConfigureFailure: Error, Equatable {}

    /// ViewModel factory と、ViewModel だけを受け取る View factory の両方を登録する。
    private static func registerBothSlots(
        in harness: DialogTestHarness,
        recorder: ModelBindingTestRecorder
    ) {
        harness.registry.register(ConfigurableTestDialogViewModel.self) {
            ConfigurableTestDialogViewModel(message: "factory の既定")
        }
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel in
            recorder.recording(
                ModelBindingTestContentView(notifier: viewModel.notifier, message: viewModel.message)
            )
        }
    }

    @Test("[MB-TS-01] 型指定 show が生成 → configure → 表示 → 結果の一連で動く")
    func typedShowCreatesConfiguresPresentsAndReturnsResult() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        let showTask = Task {
            try await harness.dialogs.show(ConfigurableTestDialogViewModel.self) { viewModel in
                viewModel.message = "configure で設定"
            }
        }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        #expect(createdView.message == "configure で設定", "configure の設定が中身に反映されていること")
        try #require(createdView.notifier).complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("[MB-TS-02] 非同期 configure の完了まで中身の生成が始まらない")
    func viewIsNotCreatedUntilAsynchronousConfigureCompletes() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)
        let gate = DialogTransitionGate()
        let configureStarted = DialogTransitionGate()

        let showTask = Task {
            try await harness.dialogs.show(ConfigurableTestDialogViewModel.self) { viewModel in
                configureStarted.open()
                try await gate.wait()
                viewModel.message = "門を通ってから設定"
            }
        }
        // configure が始まったことを確かめたうえで、門が閉じている間は中身が作られず提示も始まらないことを見る。
        try await configureStarted.wait()
        #expect(recorder.creationCount == 0)
        #expect(harness.presentedContainers.isEmpty)

        gate.open()
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        #expect(createdView.message == "門を通ってから設定")
        try #require(createdView.notifier).complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("[MB-TS-03] ViewModel factory 未登録の型指定 show は構成ミスとして失敗する")
    func typedShowWithoutViewModelFactoryFails() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel in
            recorder.recording(
                ModelBindingTestContentView(notifier: viewModel.notifier, message: viewModel.message)
            )
        }

        await #expect(throws: DialogError.viewModelFactoryNotRegistered(
            viewModelType: String(describing: ConfigurableTestDialogViewModel.self))) {
            _ = try await harness.dialogs.show(ConfigurableTestDialogViewModel.self)
        }
        #expect(recorder.creationCount == 0)
        #expect(harness.presentedContainers.isEmpty)
    }

    @Test("[MB-TS-04] configure 省略の型指定 show は ViewModel factory の生成物をそのまま表示する")
    func typedShowWithoutConfigurePresentsFactoryOutputAsIs() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        let showTask = Task { try await harness.dialogs.show(ConfigurableTestDialogViewModel.self) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        #expect(createdView.message == "factory の既定")
        try #require(createdView.notifier).complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("[MB-TS-05] configure の失敗は提示に進まず伝播する")
    func configureFailurePropagatesWithoutPresenting() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        await #expect(throws: ConfigureFailure()) {
            _ = try await harness.dialogs.show(ConfigurableTestDialogViewModel.self) { _ in
                throw ConfigureFailure()
            }
        }
        #expect(recorder.creationCount == 0, "中身の生成へ進まないこと")
        #expect(harness.presentedContainers.isEmpty)

        // 同じ型のその後の型指定 show は正常に動く。
        let showTask = Task { try await harness.dialogs.show(ConfigurableTestDialogViewModel.self) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(createdView.notifier).complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("[MB-TS-06] 再登録はスロット単位の後勝ちで他方を保持する")
    func reregistrationReplacesOnlyTheTargetSlot() async throws {
        let harness = DialogTestHarness()
        let firstRecorder = ModelBindingTestRecorder()
        Self.registerBothSlots(in: harness, recorder: firstRecorder)

        // View factory だけを別の factory で登録し直す。ViewModel factory のスロットは触らない。
        let secondRecorder = ModelBindingTestRecorder()
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel in
            secondRecorder.recording(
                ModelBindingTestContentView(notifier: viewModel.notifier, message: viewModel.message)
            )
        }

        let showTask = Task { try await harness.dialogs.show(ConfigurableTestDialogViewModel.self) }
        let createdView = try await secondRecorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        #expect(firstRecorder.creationCount == 0, "古い View factory は使われないこと")
        #expect(createdView.message == "factory の既定", "ViewModel factory は保持されていること")
        try #require(createdView.notifier).complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("[MB-IO-03] SwiftUI 登録でも VM 供給と型指定呼び出しが同じに働く")
    func swiftUIRegistrationSupportsNotifierSupplyAndTypedShow() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        harness.registry.register(ConfigurableTestDialogViewModel.self) {
            ConfigurableTestDialogViewModel(message: "SwiftUI の既定")
        }
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel in
            recorder.recording(
                message: viewModel.message,
                notifier: viewModel.notifier,
                content: Text(viewModel.message)
                    .frame(width: 240, height: 120)
            )
        }

        let showTask = Task {
            try await harness.dialogs.show(ConfigurableTestDialogViewModel.self) { viewModel in
                viewModel.message = "SwiftUI の configure"
            }
        }
        let observedMessage = try await recorder.observedMessage(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        #expect(observedMessage == "SwiftUI の configure", "configure の設定が表示へ反映されていること")
        // SwiftUI の中身が VM 経由で引いた報告口で報告する。
        try await recorder.suppliedNotifier(at: 0).complete(true)

        #expect(try await showTask.value == .completed(true))
    }
}
#endif
