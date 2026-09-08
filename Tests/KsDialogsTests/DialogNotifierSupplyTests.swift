#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("show 中の ViewModel から結果報告口を引ける", .serialized)
@MainActor
struct DialogNotifierSupplyTests {
    /// 1回目の生成だけ中身を作れない factory の呼び出し回数。
    @MainActor
    final class FactoryCallCount {
        var value = 0
    }

    @Test("[MB-NI-01] VM 引数のみの factory の中身が VM 経由の報告口で結果を返す")
    func viewModelOnlyFactoryReportsThroughSuppliedNotifier() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel in
            // 中身の生成中に引けることが要件。生成後に紐付ける実装ではここが nil になる。
            recorder.recording(
                ModelBindingTestContentView(notifier: viewModel.notifier, message: viewModel.message)
            )
        }

        let viewModel = ConfigurableTestDialogViewModel(message: "報告口の供給")
        let showTask = Task { try await harness.dialogs.show(viewModel) }
        let createdView = try await recorder.view(at: 0)

        let notifier = try #require(createdView.notifier, "中身の生成中に報告口が引けること")
        try #require(await harness.waitForPresentedContainers(count: 1))
        notifier.complete(true)

        #expect(try await showTask.value == .completed(true))
    }

    @Test("[MB-NI-02] show 前の VM からは報告口を引けない")
    func notifierIsUnavailableBeforeShow() {
        let viewModel = ConfigurableTestDialogViewModel(message: "未表示")

        #expect(viewModel.notifier == nil)
    }

    @Test("[MB-NI-03] 結果配送後の VM からは報告口を引けない")
    func notifierIsUnavailableAfterResultDelivery() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel in
            recorder.recording(
                ModelBindingTestContentView(notifier: viewModel.notifier, message: viewModel.message)
            )
        }

        let viewModel = ConfigurableTestDialogViewModel(message: "配送後")
        let showTask = Task { try await harness.dialogs.show(viewModel) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(createdView.notifier).complete(true)

        #expect(try await showTask.value == .completed(true))
        #expect(viewModel.notifier == nil, "結果が呼び出し元へ渡る時点で紐付けが外れていること")
    }

    @Test("[MB-NI-04] 同一 VM インスタンスの並行 show は構成ミスとして失敗する")
    func concurrentShowOfSameInstanceFails() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel in
            recorder.recording(
                ModelBindingTestContentView(notifier: viewModel.notifier, message: viewModel.message)
            )
        }

        let viewModel = ConfigurableTestDialogViewModel(message: "並行")
        let showTask = Task { try await harness.dialogs.show(viewModel) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        await #expect(throws: DialogError.viewModelAlreadyShowing(
            viewModelType: String(describing: ConfigurableTestDialogViewModel.self))) {
            _ = try await harness.dialogs.show(viewModel)
        }

        // 先行 show のダイアログは残ったままで、報告した結果はそちらへ配送される。
        #expect(harness.presentedContainers.count == 1)
        #expect(recorder.createdViews.count == 1)
        createdView.notifier?.complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("表示中に View factory を登録し直しても VM 経由の報告口は変わらない")
    func notifierIsUnaffectedByReregistrationDuringShow() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel in
            recorder.recording(
                ModelBindingTestContentView(notifier: viewModel.notifier, message: viewModel.message)
            )
        }

        let viewModel = ConfigurableTestDialogViewModel(message: "表示中の再登録")
        let showTask = Task { try await harness.dialogs.show(viewModel) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        // 表示したまま同じ型の View factory を差し替える。出ているダイアログの紐付けは影響を受けない。
        harness.registry.register(ConfigurableTestDialogViewModel.self) { _ in
            DialogTestContentView()
        }

        #expect(viewModel.notifier != nil, "表示中の報告口が引けること")
        try #require(createdView.notifier).complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("[MB-NI-05] 2引数 factory でも VM 経由の報告口は同じ配送先を指す")
    func notifierFromViewModelSharesDestinationWithFactoryArgument() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        harness.registry.register(ConfigurableTestDialogViewModel.self) { viewModel, _ in
            // factory 引数の報告口は使わず、VM から引いた報告口だけを中身に持たせる。
            recorder.recording(
                ModelBindingTestContentView(notifier: viewModel.notifier, message: viewModel.message)
            )
        }

        let viewModel = ConfigurableTestDialogViewModel(message: "2引数")
        let showTask = Task { try await harness.dialogs.show(viewModel) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(createdView.notifier).complete(true)

        #expect(try await showTask.value == .completed(true))
    }

    @Test("[MB-NI-06] 等価な別インスタンスの VM は互いに干渉しない")
    func equalButDistinctViewModelsDoNotInterfere() async throws {
        let harness = DialogTestHarness()
        harness.registry.register(EquatableTestDialogViewModel.self) { _ in
            DialogTestContentView()
        }

        let first = EquatableTestDialogViewModel(label: "同じラベル")
        let second = EquatableTestDialogViewModel(label: "同じラベル")
        try #require(first == second, "等価比較は一致すること")
        try #require(first !== second, "別インスタンスであること")

        let firstTask = Task { try await harness.dialogs.show(first) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let secondTask = Task { try await harness.dialogs.show(second) }
        try #require(await harness.waitForPresentedContainers(count: 2))

        try #require(second.notifier).complete(true)

        #expect(try await secondTask.value == .completed(true))
        #expect(await DialogTestWaiting.waitUntil { harness.presentedContainers.count == 1 })
        #expect(first.notifier != nil, "報告していない側は表示中のままであること")

        firstTask.cancel()
        _ = try? await firstTask.value
    }

    @Test("[MB-NI-07] 異常終了でも紐付けが外れ、同じ VM を再 show できる")
    func bindingIsRemovedOnFailureAndViewModelCanBeShownAgain() async throws {
        let harness = DialogTestHarness()
        let recorder = ModelBindingTestRecorder()
        let callCount = FactoryCallCount()
        // 1回目の中身の生成だけ失敗する factory。生成の失敗は show の失敗として throw される。
        harness.registry.register(
            DialogViewFactory { viewModel, _ in
                callCount.value += 1
                guard callCount.value > 1,
                      let typedViewModel = viewModel as? ConfigurableTestDialogViewModel else {
                    return nil
                }
                return DialogContent(
                    view: recorder.recording(
                        ModelBindingTestContentView(
                            notifier: typedViewModel.notifier,
                            message: typedViewModel.message
                        )
                    )
                )
            },
            forKey: DialogViewModelKey(ConfigurableTestDialogViewModel.self)
        )

        let viewModel = ConfigurableTestDialogViewModel(message: "再表示")
        await #expect(throws: DialogError.viewFactoryTypeMismatch(
            viewModelType: String(describing: ConfigurableTestDialogViewModel.self))) {
            _ = try await harness.dialogs.show(viewModel)
        }
        #expect(viewModel.notifier == nil, "失敗直後に紐付けが外れていること")

        let showTask = Task { try await harness.dialogs.show(viewModel) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(createdView.notifier).complete(true)

        #expect(try await showTask.value == .completed(true))
    }
}
#endif
