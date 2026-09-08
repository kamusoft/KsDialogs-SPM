#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("VM 型キーによる View 解決と毎回生成", .serialized)
@MainActor
struct DialogRegistryTests {
    @Test("登録済み VM 型の show で View が表示される")
    func registeredViewModelPresentsFactoryView() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "こんにちは")) }
        try #require(await harness.waitForPresentedContainers(count: 1))

        let container = try #require(harness.topmostContainer)
        container.loadViewIfNeeded()
        let createdView = try #require(recorder.createdViews.first)
        #expect(createdView.superview === container.view)

        recorder.notifiers[0].complete(true)
        _ = try await showTask.value
    }

    @Test("factory が投げた失敗は show の失敗になり、提示は起きない")
    func throwingFactoryFailsTheShow() async throws {
        let harness = DialogTestHarness()
        // 中身の作り手が失敗を投げる登録。互換面 (MAUI) の中身の供給元が
        // 中身を作れなかった場合もこの経路を通る。
        harness.registry.register(BasicTestDialogViewModel.self) { _, _ throws -> UIView in
            throw DialogRegistryTestContentFailure.cannotMakeContent
        }

        await #expect(throws: DialogRegistryTestContentFailure.cannotMakeContent) {
            _ = try await harness.dialogs.show(BasicTestDialogViewModel(message: "作れない中身"))
        }
        #expect(harness.presentedContainers.isEmpty, "提示は起きない")
    }

    @Test("未登録 VM 型の show は即エラー")
    func unregisteredViewModelThrows() async throws {
        let harness = DialogTestHarness()

        await #expect(throws: DialogError.viewFactoryNotRegistered(
            viewModelType: String(describing: UnregisteredTestDialogViewModel.self))) {
            _ = try await harness.dialogs.show(UnregisteredTestDialogViewModel())
        }
        #expect(harness.presentedContainers.isEmpty)
    }

    @Test("show ごとに View は新規生成される")
    func viewIsCreatedForEachShow() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let firstTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "1回目")) }
        try await recorder.notifier(at: 0).complete(true)
        _ = try await firstTask.value
        try #require(await harness.waitForPresentedContainers(count: 0))

        let secondTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "2回目")) }
        try await recorder.notifier(at: 1).complete(true)
        _ = try await secondTask.value

        #expect(recorder.createdViews.count == 2)
        #expect(recorder.createdViews[0] !== recorder.createdViews[1])
    }

    @Test("別インスタンスの同一 VM 型は独立した重ね出しになる")
    func distinctInstancesOfSameViewModelTypeAreShownAsIndependentStack() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        // 結果報告口はインスタンスごとに紐付くため、重ねるときは別インスタンスを使う (core/ADR-0018)。
        let firstTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "1枚目")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let secondTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "2枚目")) }
        try #require(await harness.waitForPresentedContainers(count: 2))

        #expect(recorder.createdViews.count == 2)
        #expect(recorder.createdViews[0] !== recorder.createdViews[1])

        recorder.notifiers[1].complete(true)
        recorder.notifiers[0].complete(false)
        #expect(try await secondTask.value == .completed(true))
        #expect(try await firstTask.value == .completed(false))
    }

    @Test("片方の入口の登録がもう片方から見える")
    func registrationIsSharedBetweenEntryPoints() async throws {
        // 既定 singleton エントリのレジストリへ登録し、DI 注入相当の別インスタンスから show する。
        let recorder = DialogTestRecorder<Bool>()
        Dialog.shared.registry.register(SharedRegistryTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let harness = DialogTestHarness(registry: .shared)
        let injected: any KsDialog = harness.dialogs

        let showTask = Task { try await injected.show(SharedRegistryTestDialogViewModel()) }
        let notifier = try await recorder.notifier(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))
        notifier.complete(true)

        #expect(try await showTask.value == .completed(true))
    }
}

/// 中身の作り手が投げる失敗。factory の例外が show の失敗として返ることの再現に使う。
enum DialogRegistryTestContentFailure: Error, Equatable {
    case cannotMakeContent
}
#endif
