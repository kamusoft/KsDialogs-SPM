#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// カスタム Loading View の登録と表示 (core/ADR-0005・0011・0013・0022) を確かめる。
///
/// 登録は Loading 専用のレジストリで行い、Dialog のレジストリとは独立している。
/// 表示は登録済み ViewModel の instance 渡しと、その場の factory によるインライン版を持ち、
/// View は表示のたびに作り直す使い捨てである。
@Suite("カスタム Loading View の登録と表示", .serialized)
@MainActor
struct LoadingCustomViewTests {
    private static let contentSize = CGSize(width: 120, height: 80)

    @Test("[LD-CV-01] 登録済み VM でカスタム Loading が表示される")
    func LD_CV_01_registeredViewModelPresentsCustomView() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            viewRecorder.record(view)
            return view
        }

        try await harness.loading.show(LoadingTestViewModel())

        let presentedView = try #require(harness.contentView)
        #expect(presentedView === viewRecorder.lastView, "factory が生成した View が表示される")
        #expect(presentedView.window === harness.window)
        #expect(harness.coordinator.presentedBuiltinContentView == nil, "既定ローディングは使われない")

        await harness.loading.hide()

        #expect(harness.isPresenting == false)
        #expect(presentedView.window == nil, "hide で消える")
    }

    @Test("[LD-CV-02] 宣言的 UI 系の登録でも同じに働く")
    func LD_CV_02_declarativeRegistrationBehavesLikeUIKit() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let appearanceRecorder = LoadingTestAppearanceRecorder()
        harness.registry.register(ProgressReceivingLoadingTestViewModel.self) { _ in
            LoadingSwiftUIProbeContent(
                contentSize: Self.contentSize,
                recorder: appearanceRecorder
            )
        }
        let viewModel = ProgressReceivingLoadingTestViewModel()
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start(viewModel) { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())

        let presentedView = try #require(harness.contentView)
        #expect(presentedView.window === harness.window, "従来 View 系と同じく画面に載る")
        #expect(harness.coordinator.presentedContainer?.contentHost != nil, "ホストごと器に組み込まれる")
        #expect(await DialogTestWaiting.waitUntil { appearanceRecorder.appearCount >= 1 }, "中身に出現が届く")

        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })
        reporter.report(0.6)
        try #require(
            await DialogTestWaiting.waitUntil { viewModel.receivedProgress == [0.6] },
            "進捗転送も従来 View 系と同じ"
        )

        gate.open()
        try await scope.value
        #expect(harness.isPresenting == false)
        #expect(presentedView.window == nil, "撤去も同じ")
        #expect(harness.coordinator.presentedContainer == nil)
    }

    @Test("[LD-CV-03] インライン factory 表示はレジストリを変えない")
    func LD_CV_03_inlineFactoryDoesNotTouchRegistry() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let registeredRecorder = LoadingTestViewRecorder()
        let inlineRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            registeredRecorder.record(view)
            return view
        }

        try await harness.loading.show(LoadingTestViewModel()) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            inlineRecorder.record(view)
            return view
        }

        #expect(harness.contentView === inlineRecorder.lastView, "インラインの View が使われる")
        #expect(registeredRecorder.views.isEmpty, "登録済み factory は呼ばれない")

        await harness.loading.hide()

        try await harness.loading.show(LoadingTestViewModel())

        #expect(harness.contentView === registeredRecorder.lastView, "その後の通常表示は登録済み factory を使う")
        #expect(registeredRecorder.views.count == 1)
        #expect(inlineRecorder.views.count == 1, "インライン表示は登録を書き換えない")

        await harness.loading.hide()
    }

    @Test("[LD-CV-04] 未登録 VM の表示は構成ミスとして失敗し action は実行されない")
    func LD_CV_04_unregisteredViewModelFailsFast() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTestActionRecorder()

        await #expect(throws: DialogError.self) {
            try await harness.loading.show(UnregisteredLoadingTestViewModel())
        }
        #expect(harness.isPresenting == false, "表示されない")

        await #expect(throws: DialogError.self) {
            try await harness.loading.start(UnregisteredLoadingTestViewModel()) { _ in
                await recorder.recordCompletion()
            }
        }
        #expect(recorder.completionCount == 0, "action は実行されない")
        #expect(harness.isPresenting == false)
        #expect(harness.coordinator.coalescedUseCount == 0, "合流も始まらない")
    }

    @Test("[LD-CV-05] Dialog と Loading のレジストリは独立している")
    func LD_CV_05_dialogAndLoadingRegistriesAreIndependent() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let dialogHarness = DialogTestHarness()
        let dialogRecorder = DialogTestRecorder<Bool>()
        let firstLoadingRecorder = LoadingTestViewRecorder()
        let secondLoadingRecorder = LoadingTestViewRecorder()

        dialogHarness.registry.register(DualRegistryLoadingTestViewModel.self) { _, notifier in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            dialogRecorder.record(view: view, notifier: notifier)
            return view
        }
        harness.registry.register(DualRegistryLoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            firstLoadingRecorder.record(view)
            return view
        }
        // Loading 側だけを別の factory で再登録する (後勝ち)。
        harness.registry.register(DualRegistryLoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            secondLoadingRecorder.record(view)
            return view
        }

        try await harness.loading.show(DualRegistryLoadingTestViewModel())
        #expect(harness.contentView === secondLoadingRecorder.lastView, "Loading は再登録後の View を使う")
        #expect(firstLoadingRecorder.views.isEmpty)
        await harness.loading.hide()

        let showTask = Task { try await dialogHarness.dialogs.show(DualRegistryLoadingTestViewModel()) }
        try #require(await dialogHarness.waitForPresentedContainers(count: 1))
        let dialogContainer = try #require(dialogHarness.topmostContainer)

        #expect(
            dialogContainer.contentView === dialogRecorder.createdViews.last,
            "Dialog は Loading 側の再登録に影響されない"
        )

        let notifier = try await dialogRecorder.notifier(at: 0)
        notifier.complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("[LD-CV-06] View は表示のたびに生成される")
    func LD_CV_06_viewIsCreatedForEachDisplay() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            viewRecorder.record(view)
            return view
        }
        let viewModel = LoadingTestViewModel()

        try await harness.loading.show(viewModel)
        let firstView = try #require(harness.contentView)
        await harness.loading.hide()

        try await harness.loading.show(viewModel)
        let secondView = try #require(harness.contentView)
        await harness.loading.hide()

        #expect(viewRecorder.views.count == 2, "factory は表示のたびに呼ばれる")
        #expect(firstView !== secondView, "毎回新しい View が使われる")
    }

    @Test("[LD-IO-02] SwiftUI 登録のカスタム Loading が UIKit 登録と同じに働く")
    func LD_IO_02_swiftUIRegistrationMatchesUIKitRegistration() async throws {
        let uiKitObservation = try await observeDisplay { registry in
            registry.register(ProgressReceivingLoadingTestViewModel.self) { _ in
                FixedContentSizeView(contentSize: Self.contentSize)
            }
        }
        let swiftUIObservation = try await observeDisplay { registry in
            registry.register(ProgressReceivingLoadingTestViewModel.self) { _ in
                FixedSizeSwiftUIContent(contentSize: Self.contentSize)
            }
        }

        #expect(swiftUIObservation == uiKitObservation, "表示・進捗転送・撤去の観察が一致する")
    }

    /// 表示・進捗転送・撤去の観察をひとまとめにしたもの。登録の技術が変わっても同じ値になる。
    private struct DisplayObservation: Equatable {
        let didPresentOnWindow: Bool
        let receivedProgress: [Double]
        let didRemoveFromWindow: Bool
        let isPresentingAfterScope: Bool
    }

    /// 渡した登録で表示・進捗報告・撤去まで通し、観察できた結果を返す。
    private func observeDisplay(
        register: @MainActor (LoadingViewRegistry) -> Void
    ) async throws -> DisplayObservation {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let viewModel = ProgressReceivingLoadingTestViewModel()
        register(harness.registry)
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start(viewModel) { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        let presentedView = try #require(harness.contentView)
        let didPresentOnWindow = presentedView.window === harness.window

        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })
        reporter.report(0.5)
        _ = await DialogTestWaiting.waitUntil { viewModel.receivedProgress.isEmpty == false }

        gate.open()
        try await scope.value

        return DisplayObservation(
            didPresentOnWindow: didPresentOnWindow,
            receivedProgress: viewModel.receivedProgress,
            didRemoveFromWindow: presentedView.window == nil,
            isPresentingAfterScope: harness.isPresenting
        )
    }
}
#endif
