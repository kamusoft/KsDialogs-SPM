#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 提示先が無いまま始まった Loading の表示を確かめる。
///
/// 処理は通常どおり実行したまま提示先の出現を待ち、現れた時点で表示が続いていれば
/// 中身を作って入りの演出から表示する。現れる前に表示が終われば何も表示しない。
/// 中身を作る時点は開始時点の提示先の有無で決まり、失敗の見え方もそれに従う。
@Suite("提示先が無いまま始まった Loading", .serialized)
@MainActor
struct LoadingHostWaitTests {
    private static let contentSize = CGSize(width: 120, height: 80)

    /// 提示先が現れたことにする (取り付け先を戻して、提示先の出現の合図を送る)。
    private static func makeHostAppear(_ harness: LoadingTestHarness) {
        harness.surface.hostView = harness.window
        harness.surface.fireHostAppearance()
    }

    @Test("[LD-HW-01] 提示先が現れた時点で処理中なら、入りのフックを経て表示される")
    func LD_HW_01_presentsThroughPresentationHookWhenHostAppearsDuringAction() async throws {
        let harness = LoadingTestHarness(hasHost: false)
        defer { harness.tearDown() }
        let probe = DialogTransitionProbe()
        let viewRecorder = LoadingTestViewRecorder()
        let gate = DialogTransitionGate()

        let scope = Task {
            try await harness.loading.start(LoadingTestViewModel(), factory: { _ in
                let view = FixedContentSizeView(contentSize: Self.contentSize)
                view.ksDialogTransition = DialogTransition(
                    presentation: probe.immediateHook(.presentation),
                    dismissal: probe.immediateHook(.dismissal)
                )
                viewRecorder.record(view)
                return view
            }) { _ in
                try await gate.wait()
                return 42
            }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.coalescedUseCount == 1 })
        #expect(harness.coordinator.isWaitingForHost, "提示先の出現を待っている")
        #expect(viewRecorder.views.isEmpty, "提示先が無い間は中身を作らない")
        #expect(harness.isPresenting == false)

        Self.makeHostAppear(harness)

        #expect(viewRecorder.views.count == 1, "提示先が現れた時点で中身が作られる")
        #expect(await harness.waitUntilPresenting(), "表示される")
        #expect(harness.contentView === viewRecorder.lastView)
        #expect(
            await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 },
            "入りのフックを経て表示される"
        )

        gate.open()
        #expect(try await scope.value == 42, "スコープ形は action の戻り値を返す")
        #expect(harness.isPresenting == false, "action が終わると閉じる")
        #expect(harness.surface.hostAppearance.activeRegistrationCount == 0)
    }

    @Test("[LD-HW-02] 提示先が現れる前に処理が終われば、何も表示されない")
    func LD_HW_02_nothingIsPresentedWhenActionEndsBeforeHostAppears() async throws {
        let harness = LoadingTestHarness(hasHost: false)
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()

        let value = try await harness.loading.start(LoadingTestViewModel(), factory: { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            viewRecorder.record(view)
            return view
        }) { _ in 7 }
        #expect(value == 7, "スコープ形は action の戻り値を返す")

        Self.makeHostAppear(harness)

        #expect(viewRecorder.views.isEmpty, "中身は作られない")
        #expect(harness.isPresenting == false, "表示されない")
        #expect(harness.attachedContainerViews.isEmpty)
        #expect(harness.coordinator.isWaitingForHost == false, "待ちもやめている")
    }

    @Test("[LD-HW-03] 提示先が現れる前に hide されれば、何も表示されない")
    func LD_HW_03_nothingIsPresentedWhenHiddenBeforeHostAppears() async throws {
        let harness = LoadingTestHarness(hasHost: false)
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()

        try await harness.loading.show(LoadingTestViewModel()) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            viewRecorder.record(view)
            return view
        }
        #expect(harness.coordinator.isWaitingForHost, "提示先の出現を待っている")

        await harness.loading.hide()
        Self.makeHostAppear(harness)

        #expect(viewRecorder.views.isEmpty, "中身は作られない")
        #expect(harness.isPresenting == false, "表示されない")
        #expect(harness.attachedContainerViews.isEmpty)
        #expect(harness.surface.hostAppearance.activeRegistrationCount == 0, "待ちの購読は解除される")
    }

    @Test("[LD-HW-04] 提示先が現れた時点の中身の生成に失敗すると、表示だけを諦めて処理は続く")
    func LD_HW_04_contentFailureAfterHostAppearsAbandonsOnlyThePresentation() async throws {
        let harness = LoadingTestHarness(hasHost: false)
        defer { harness.tearDown() }
        let gate = DialogTransitionGate()
        let actionRecorder = LoadingTestActionRecorder()

        let scope = Task {
            try await harness.loading.start(
                LoadingTestViewModel(),
                factory: { _ throws -> UIView in throw LoadingStartTestContentFailure.cannotMakeContent }
            ) { _ in
                try await gate.wait()
                actionRecorder.recordCompletion()
                return 5
            }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.coalescedUseCount == 1 })

        Self.makeHostAppear(harness)

        #expect(harness.warnings.messages.count == 1, "警告ログが残る")
        #expect(
            harness.warnings.messages.first?.hasPrefix("Could not create the Loading content. Nothing is presented") == true,
            "警告の本文: \(harness.warnings.messages)"
        )
        #expect(harness.isPresenting == false, "Loading は表示されない")
        #expect(harness.attachedContainerViews.isEmpty)
        #expect(harness.coordinator.coalescedUseCount == 1, "合流状態は残る")
        #expect(harness.surface.hostAppearance.activeRegistrationCount == 0, "作り直しを試みないので待ちもやめる")

        gate.open()
        #expect(try await scope.value == 5, "action はそのまま続き、失敗は返らない")
        #expect(actionRecorder.completionCount == 1)
        #expect(harness.coordinator.coalescedUseCount == 0)
    }

    @Test("[LD-HW-05] 表示の前に報告した進捗も VM の受け口へ届く")
    func LD_HW_05_progressReachesViewModelBeforePresentation() async throws {
        let harness = LoadingTestHarness(hasHost: false)
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(ProgressReceivingLoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            viewRecorder.record(view)
            return view
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
        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })

        reporter.report(0.25)

        #expect(
            await DialogTestWaiting.waitUntil { viewModel.receivedProgress == [0.25] },
            "表示の前の進捗が VM の受け口へ届く"
        )
        #expect(harness.isPresenting == false, "まだ表示されていない")
        #expect(viewRecorder.views.isEmpty)

        gate.open()
        try await scope.value
    }

    @Test("[LD-HW-06] 開始時点で提示先があれば、中身の生成の失敗は今までどおり開始の失敗になる")
    func LD_HW_06_contentFailureWithHostFailsTheStart() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let actionRecorder = LoadingTestActionRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ throws -> UIView in
            throw LoadingStartTestContentFailure.cannotMakeContent
        }

        await #expect(throws: LoadingStartTestContentFailure.cannotMakeContent) {
            try await harness.loading.start(LoadingTestViewModel()) { _ in
                await MainActor.run { actionRecorder.recordCompletion() }
            }
        }

        #expect(actionRecorder.completionCount == 0, "action は実行されない")
        #expect(harness.coordinator.coalescedUseCount == 0)
        #expect(harness.warnings.messages.isEmpty, "開始の失敗として返るので警告にはしない")
    }

    @Test("[LD-HW-07] 提示先が無くても、未登録のカスタム Loading は開始の時点で失敗する")
    func LD_HW_07_unregisteredViewModelFailsTheStartWithoutHost() async throws {
        let harness = LoadingTestHarness(hasHost: false)
        defer { harness.tearDown() }
        let actionRecorder = LoadingTestActionRecorder()

        await #expect(throws: DialogError.viewFactoryNotRegistered(
            viewModelType: String(describing: UnregisteredLoadingTestViewModel.self))) {
            try await harness.loading.start(UnregisteredLoadingTestViewModel()) { _ in
                await MainActor.run { actionRecorder.recordCompletion() }
            }
        }

        #expect(actionRecorder.completionCount == 0, "action は実行されない")
        #expect(harness.coordinator.coalescedUseCount == 0, "合流も始まらない")
        #expect(harness.coordinator.isWaitingForHost == false, "待ちも始まらない")
    }
}
#endif
