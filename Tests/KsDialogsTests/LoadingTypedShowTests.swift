#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// Loading の ViewModel の型を渡す表示 (core/ADR-0035) を確かめる。
///
/// ViewModel はレジストリの ViewModel factory が作り、実行順序は
/// 「ViewModel 生成 → configure 完了 → 進捗の受け口の紐付け → 中身の生成 → 表示」で固定される。
/// 合流・置き場所・進捗転送の意味はインスタンスを渡す表示と同じで、
/// 生成と configure の失敗は表示に進まず呼び出し元へ伝わる。
@Suite("Loading の ViewModel の型を渡す表示", .serialized)
@MainActor
struct LoadingTypedShowTests {
    private static let contentSize = CGSize(width: 120, height: 80)

    /// configure が投げる、テスト専用の失敗。
    struct ConfigureFailure: Error, Equatable {}

    /// 未登録の型として観察するときに使う名前。
    private static var configurableViewModelTypeName: String {
        String(describing: ConfigurableLoadingTestViewModel.self)
    }

    /// ViewModel factory と View factory の両スロットを登録する。
    private static func registerBothSlots(
        in harness: LoadingTestHarness,
        recorder: LoadingTypedShowRecorder,
        factoryTitle: String = "factory の既定"
    ) {
        harness.registry.register(ConfigurableLoadingTestViewModel.self) {
            let viewModel = ConfigurableLoadingTestViewModel(title: factoryTitle)
            recorder.recordCreation(viewModel)
            return viewModel
        }
        registerViewFactory(in: harness, recorder: recorder)
    }

    /// View factory のスロットだけを登録する。
    private static func registerViewFactory(
        in harness: LoadingTestHarness,
        recorder: LoadingTypedShowRecorder
    ) {
        harness.registry.register(ConfigurableLoadingTestViewModel.self) { viewModel in
            recorder.recordContent(title: viewModel.title)
            return FixedContentSizeView(contentSize: Self.contentSize)
        }
    }

    // MARK: - レジストリの2スロット

    @Test("[LD-TY-01] VM factory の再登録は View factory を保持する")
    func LD_TY_01_reregistrationReplacesOnlyTheTargetSlot() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let first = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: first)

        // ViewModel factory だけを登録し直す。View factory のスロットは触らない。
        harness.registry.register(ConfigurableLoadingTestViewModel.self) {
            ConfigurableLoadingTestViewModel(title: "新しい VM factory")
        }
        try await harness.loading.show(ConfigurableLoadingTestViewModel.self)

        #expect(first.observedTitles == ["新しい VM factory"], "新しい VM factory の生成物が使われる")
        #expect(harness.contentView is FixedContentSizeView, "View factory は登録時のものが保持される")
        await harness.loading.hide()

        // 逆に View factory だけを登録し直しても ViewModel factory は保持される。
        let second = LoadingTypedShowRecorder()
        Self.registerViewFactory(in: harness, recorder: second)
        try await harness.loading.show(ConfigurableLoadingTestViewModel.self)

        #expect(second.observedTitles == ["新しい VM factory"], "VM factory は保持される")
        #expect(first.creationCount == 1, "古い View factory は使われない")
        await harness.loading.hide()
    }

    @Test("[LD-TY-02] 表示中の再登録は出ている Loading に影響しない")
    func LD_TY_02_reregistrationDoesNotAffectPresentedLoading() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let first = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: first, factoryTitle: "最初の VM")
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start(ConfigurableLoadingTestViewModel.self) { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        let presentedView = try #require(harness.contentView)
        let displayedViewModel = try #require(first.createdViewModels.first)

        let second = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: second, factoryTitle: "後の VM")

        #expect(harness.contentView === presentedView, "表示中の中身は変わらない")
        #expect(second.createdViewModels.isEmpty, "再登録だけでは新しい VM は作られない")
        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })
        reporter.report(0.4)
        #expect(
            await DialogTestWaiting.waitUntil { displayedViewModel.receivedProgress == [0.4] },
            "進捗転送先も変わらない"
        )

        gate.open()
        try await scope.value

        // 次の表示からは新しい登録が使われる。
        try await harness.loading.show(ConfigurableLoadingTestViewModel.self)
        #expect(second.observedTitles == ["後の VM"])
        await harness.loading.hide()
    }

    // MARK: - 型指定 show

    @Test("[LD-TY-03] 型指定 show が生成 → configure → 表示の一連で動く")
    func LD_TY_03_typedShowCreatesConfiguresAndPresents() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        try await harness.loading.show(ConfigurableLoadingTestViewModel.self) { viewModel in
            viewModel.title = "configure で設定"
        }

        #expect(recorder.createdViewModels.count == 1, "VM factory の生成物が使われる")
        #expect(recorder.observedTitles == ["configure で設定"], "configure の設定を中身の生成が読める")
        #expect(harness.contentView is FixedContentSizeView)
        #expect(harness.isPresenting)
        #expect(harness.coordinator.coalescedUseCount == 1)
        await harness.loading.hide()
    }

    @Test("[LD-TY-04] 非同期 configure の完了まで View 生成が始まらない")
    func LD_TY_04_viewIsNotCreatedUntilAsynchronousConfigureCompletes() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)
        let gate = DialogTransitionGate()
        let configureStarted = DialogTransitionGate()

        let showTask = Task {
            try await harness.loading.show(ConfigurableLoadingTestViewModel.self) { viewModel in
                configureStarted.open()
                try await gate.wait()
                viewModel.title = "門を通ってから設定"
            }
        }
        try await configureStarted.wait()

        #expect(recorder.creationCount == 0, "configure の完了前は View factory が呼ばれない")
        #expect(harness.isPresenting == false)

        gate.open()
        try await showTask.value

        #expect(recorder.observedTitles == ["門を通ってから設定"])
        #expect(harness.isPresenting)
        await harness.loading.hide()
    }

    @Test("[LD-TY-05] VM factory 未登録の型指定 show は構成ミスとして失敗する")
    func LD_TY_05_typedShowWithoutViewModelFactoryFails() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerViewFactory(in: harness, recorder: recorder)

        await #expect(throws: DialogError.viewModelFactoryNotRegistered(
            viewModelType: Self.configurableViewModelTypeName)) {
            try await harness.loading.show(ConfigurableLoadingTestViewModel.self)
        }

        #expect(recorder.creationCount == 0)
        #expect(harness.isPresenting == false)
        #expect(harness.coordinator.coalescedUseCount == 0, "合流数は変わらない")
    }

    @Test("[LD-TY-06] configure の失敗は提示に進まず伝播する")
    func LD_TY_06_configureFailurePropagatesWithoutPresenting() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        await #expect(throws: ConfigureFailure()) {
            try await harness.loading.show(ConfigurableLoadingTestViewModel.self) { _ in
                throw ConfigureFailure()
            }
        }

        #expect(recorder.creationCount == 0, "中身の生成へ進まない")
        #expect(harness.isPresenting == false)
        #expect(harness.coordinator.coalescedUseCount == 0, "合流1件として数えない")

        // 同じ型のその後の型指定 show は正常に動く。
        try await harness.loading.show(ConfigurableLoadingTestViewModel.self)
        #expect(harness.isPresenting)
        await harness.loading.hide()
    }

    @Test("[LD-TY-07] configure 省略の型指定 show は VM factory の生成物をそのまま表示する")
    func LD_TY_07_typedShowWithoutConfigurePresentsFactoryOutputAsIs() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        try await harness.loading.show(ConfigurableLoadingTestViewModel.self)

        #expect(recorder.observedTitles == ["factory の既定"])
        #expect(harness.isPresenting)
        await harness.loading.hide()
    }

    @Test("[LD-TY-08] 型指定 show で生成した VM にも進捗が転送される")
    func LD_TY_08_progressReachesGeneratedViewModel() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start(ConfigurableLoadingTestViewModel.self) { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        // 受け口は MainActor に閉じた ViewModel なので、届いた時点で UI スレッド上にいる。
        let createdViewModel = try #require(recorder.createdViewModels.first)

        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })
        reporter.report(0.6)

        #expect(await DialogTestWaiting.waitUntil { createdViewModel.receivedProgress == [0.6] })

        gate.open()
        try await scope.value
    }

    // MARK: - 型指定 start

    @Test("[LD-TY-09] 型指定 start が処理の戻り値を返し合流1件を対で数える")
    func LD_TY_09_typedStartReturnsValueAndCountsSingleUse() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)
        let gate = DialogTransitionGate()

        let scope = Task {
            try await harness.loading.start(ConfigurableLoadingTestViewModel.self) { _ in
                try await gate.wait()
                return 42
            }
        }
        try #require(await harness.waitUntilPresenting(), "処理の実行中は表示される")
        #expect(harness.coordinator.coalescedUseCount == 1)

        gate.open()

        #expect(try await scope.value == 42)
        #expect(harness.coordinator.coalescedUseCount == 0, "終了で合流1件が減る")
        #expect(harness.isPresenting == false)
    }

    @Test("[LD-TY-10] 型指定 start の VM factory 未登録は処理を実行しない")
    func LD_TY_10_typedStartWithoutViewModelFactoryDoesNotRunAction() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerViewFactory(in: harness, recorder: recorder)
        let actionRecorder = LoadingTestActionRecorder()

        await #expect(throws: DialogError.viewModelFactoryNotRegistered(
            viewModelType: Self.configurableViewModelTypeName)) {
            _ = try await harness.loading.start(ConfigurableLoadingTestViewModel.self) { _ in
                await MainActor.run { actionRecorder.recordCompletion() }
            }
        }

        #expect(actionRecorder.completionCount == 0, "処理は実行されない")
        #expect(harness.isPresenting == false)
    }

    // MARK: - 置き場所とスナップショット

    @Test("[LD-TY-11] 型指定 show の置き場所引数が提示に渡る")
    func LD_TY_11_placementArgumentReachesPresentation() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)
        let placement = DialogPlacement(
            horizontalAlignment: .start,
            verticalAlignment: .start,
            offsetX: 10,
            offsetY: 20
        )
        let tolerance = DialogLayoutCaseLoader.table.tolerance

        try await harness.loading.show(ConfigurableLoadingTestViewModel.self, placement: placement)
        let typedFrame = try #require(harness.contentView).frame
        await harness.loading.hide()

        // 基準は可視領域 (上 59) から余白 24 を控除した有効領域の前端 + オフセット。
        #expect(abs(Double(typedFrame.minX) - (24 + 10)) <= tolerance, "実測 \(typedFrame)")
        #expect(abs(Double(typedFrame.minY) - (59 + 24 + 20)) <= tolerance, "実測 \(typedFrame)")

        // インスタンス渡し show と同じ位置になる。
        try await harness.loading.show(
            ConfigurableLoadingTestViewModel(title: "インスタンス渡し"),
            placement: placement
        )
        let instanceFrame = try #require(harness.contentView).frame
        await harness.loading.hide()

        #expect(typedFrame == instanceFrame)
    }

    @Test("[LD-TY-12] 型指定 show は呼び出し時点のエントリで View まで作る")
    func LD_TY_12_typedShowUsesEntrySnapshotTakenAtCall() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let first = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: first, factoryTitle: "最初の VM")
        let gate = DialogTransitionGate()
        let configureStarted = DialogTransitionGate()

        let showTask = Task {
            try await harness.loading.show(ConfigurableLoadingTestViewModel.self) { _ in
                configureStarted.open()
                try await gate.wait()
            }
        }
        try await configureStarted.wait()

        // configure の完了前に両スロットを登録し直す。
        let second = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: second, factoryTitle: "後の VM")

        gate.open()
        try await showTask.value

        #expect(first.observedTitles == ["最初の VM"], "最初に取得した VM factory と View factory の組で表示される")
        #expect(second.createdViewModels.isEmpty, "再登録後の VM factory は使われない")
        #expect(second.creationCount == 0, "再登録後の View factory は使われない")
        await harness.loading.hide()
    }

    // MARK: - 合流

    @Test("[LD-TY-14] 表示中の型指定 start は既存の表示に合流し生成した VM は表示に使われない")
    func LD_TY_14_typedStartCoalescesIntoExistingDisplay() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        await harness.loading.show(message: "先の表示")
        let presentedView = try #require(harness.contentView)

        let scope = Task {
            try await harness.loading.start(
                ConfigurableLoadingTestViewModel.self,
                configure: { viewModel in viewModel.title = "合流側の configure" }
            ) { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await DialogTestWaiting.waitUntil { harness.coordinator.coalescedUseCount == 2 })

        let createdViewModel = try #require(recorder.createdViewModels.first)
        #expect(createdViewModel.title == "合流側の configure", "VM factory と configure は実行される")
        #expect(recorder.creationCount == 0, "View factory は呼ばれない")
        #expect(harness.contentView === presentedView, "中身は最初の開始のまま")

        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })
        reporter.report(0.5)
        #expect(
            await DialogTestWaiting.waitUntil { harness.builtinText == "先の表示\n50%" },
            "進捗は表示中のコンテンツへ後勝ちで届く"
        )

        gate.open()
        try await scope.value

        #expect(harness.coordinator.coalescedUseCount == 1, "処理の終了で合流数が1減る")
        #expect(harness.isPresenting, "先の表示は残る")
        await harness.loading.hide()
    }

    @Test("[LD-TY-15] 非同期 configure の間に別の開始が表示を確定すると合流側になる")
    func LD_TY_15_typedShowJoinsDisplayStartedDuringConfigure() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)
        let instanceViewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            instanceViewRecorder.record(view)
            return view
        }
        let gate = DialogTransitionGate()
        let configureStarted = DialogTransitionGate()

        let showTask = Task {
            try await harness.loading.show(ConfigurableLoadingTestViewModel.self) { _ in
                configureStarted.open()
                try await gate.wait()
            }
        }
        try await configureStarted.wait()

        // configure の完了前に、別のインスタンス渡し show が表示を確定させる。
        try await harness.loading.show(LoadingTestViewModel())
        let instanceContentView = try #require(harness.contentView)

        gate.open()
        try await showTask.value

        #expect(harness.coordinator.coalescedUseCount == 2, "型指定 show は合流側になる")
        #expect(recorder.creationCount == 0, "View factory は呼ばれない")
        #expect(harness.contentView === instanceContentView, "中身は先に開始した show のもの")
        await harness.loading.hide()
    }

    // MARK: - 宣言的 UI 系の登録

    @Test("[LD-YI-02] SwiftUI 登録でも型指定 show が同じに働く")
    func LD_YI_02_swiftUIRegistrationSupportsTypedShow() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let recorder = LoadingTypedShowRecorder()
        let appearanceRecorder = LoadingTestAppearanceRecorder()
        harness.registry.register(ConfigurableLoadingTestViewModel.self) {
            ConfigurableLoadingTestViewModel(title: "SwiftUI の既定")
        }
        harness.registry.register(ConfigurableLoadingTestViewModel.self) { viewModel in
            recorder.recordContent(title: viewModel.title)
            return LoadingSwiftUIProbeContent(
                contentSize: Self.contentSize,
                recorder: appearanceRecorder
            )
        }

        try await harness.loading.show(ConfigurableLoadingTestViewModel.self) { viewModel in
            viewModel.title = "SwiftUI の configure"
        }

        #expect(recorder.observedTitles == ["SwiftUI の configure"], "configure の設定が表示へ反映される")
        #expect(harness.coordinator.presentedContainer?.contentHost != nil, "ホストごと器に組み込まれる")
        #expect(await DialogTestWaiting.waitUntil { appearanceRecorder.appearCount >= 1 }, "中身に出現が届く")
        await harness.loading.hide()
    }
}
#endif
