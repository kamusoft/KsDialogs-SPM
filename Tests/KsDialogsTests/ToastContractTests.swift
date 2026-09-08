#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Toast の公開面と fire-and-forget の契約 (core/ADR-0028・0029・0031) を確かめる。
///
/// show は戻り値を持たず、消滅の契機は duration の経過だけである。
/// 構成ミス (未登録の ViewModel 型) だけが呼び出し時点の失敗になり、
/// 受理した後の失敗はその表示1枚の破棄に留まる。
@Suite("Toast の公開面と fire-and-forget", .serialized)
@MainActor
struct ToastContractTests {
    /// 表示が消える前後を見分けるために使う短い duration。
    private static let shortDuration = 400

    /// 期限が来ていないことを確かめる時点。短い duration の半分より手前に置く。
    private static let beforeDeadline = Duration.milliseconds(120)

    /// 観察の途中で期限が来ないだけの長さ。
    private static let longDuration = 5000

    @Test("[TS-CO-01] show で表示され duration 経過で自動的に消える")
    func TS_CO_01_showsAndDisappearsAfterDuration() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        harness.toast.show(message: "保存しました", duration: Self.shortDuration)

        try #require(await harness.waitUntilPresenting(), "受理された表示は器ごと取り付く")
        let contentView = try #require(harness.contentViews.first)
        #expect(contentView is ToastDefaultContentView, "デフォルト View で表示される")
        #expect(contentView.window === harness.window)

        try await Task.sleep(for: Self.beforeDeadline)
        #expect(harness.displayCount == 1, "期限が来るまでは表示され続ける")

        #expect(await harness.waitUntilEmpty(), "duration の経過で自動的に消える")
        #expect(contentView.window == nil)
        #expect(harness.attachedContainerViews.isEmpty)
    }

    @Test("[TS-CO-02] duration 省略時は ToastStyle の既定が使われる")
    func TS_CO_02_omittedDurationUsesStyleDefault() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        harness.toast.style = ToastStyle(defaultDuration: Self.shortDuration)

        harness.toast.show(message: "既定 duration")

        try #require(await harness.waitUntilPresenting())
        try await Task.sleep(for: Self.beforeDeadline)
        #expect(harness.displayCount == 1, "style の既定 duration までは表示され続ける")

        #expect(await harness.waitUntilEmpty(), "style の既定 duration の経過で消える")
    }

    @Test(
        "[TS-CO-03] 0 以下の duration は style の既定に丸められる",
        arguments: [0, -1, -1000]
    )
    func TS_CO_03_nonPositiveDurationFallsBackToStyleDefault(duration: Int) async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        harness.toast.style = ToastStyle(defaultDuration: Self.shortDuration)

        harness.toast.show(message: "無効な duration", duration: duration)

        try #require(await harness.waitUntilPresenting(), "表示そのものは行われる")
        try await Task.sleep(for: Self.beforeDeadline)
        #expect(harness.displayCount == 1, "即時消滅にならない")

        #expect(await harness.waitUntilEmpty(), "永続表示にもならず、style の既定で消える")
    }

    @Test("[TS-CO-03] style の既定 duration が 0 以下でも内蔵既定へ丸められる")
    func TS_CO_03_nonPositiveStyleDefaultFallsBackToBuiltin() {
        let resolved = ToastCoordinator.effectiveDuration(nil, style: ToastStyle(defaultDuration: 0))
        #expect(resolved == ToastStyle.builtinDefaultDuration)
        let resolvedFromArgument = ToastCoordinator.effectiveDuration(
            -5,
            style: ToastStyle(defaultDuration: -1)
        )
        #expect(resolvedFromArgument == ToastStyle.builtinDefaultDuration)
    }

    @Test("[TS-CO-04] 未登録の ViewModel 型は fail-fast")
    func TS_CO_04_unregisteredViewModelFailsFast() async {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        #expect(throws: DialogError.viewFactoryNotRegistered(
            viewModelType: String(describing: UnregisteredToastTestViewModel.self)
        )) {
            try harness.toast.show(UnregisteredToastTestViewModel())
        }

        await harness.drainAcceptance()
        #expect(harness.displayCount == 0, "表示は行われない")
        #expect(harness.attachedContainerViews.isEmpty)
    }

    @Test("[TS-CO-05] インライン経路はレジストリの状態を変えない")
    func TS_CO_05_inlineShowLeavesRegistryUnchanged() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        harness.registry.register(ToastTestViewModel.self) { _ in
            let view = UIView()
            view.tag = 1
            return view
        }
        let key = DialogViewModelKey(ToastTestViewModel.self)
        let registeredBefore = try #require(harness.registry.factory(forKey: key))
        #expect(try registeredBefore.makeContent(ToastTestViewModel())?.view.tag == 1)

        try harness.toast.show(ToastTestViewModel(), duration: Self.shortDuration) { _ in
            let view = UIView()
            view.tag = 2
            return view
        }

        try #require(await harness.waitUntilPresenting())
        #expect(harness.contentViews.first?.tag == 2, "インラインの factory が使われる")

        let registeredAfter = try #require(harness.registry.factory(forKey: key))
        #expect(
            try registeredAfter.makeContent(ToastTestViewModel())?.view.tag == 1,
            "登録内容は呼び出しの前後で変化しない"
        )
    }

    @Test("[TS-CO-06] Native 内の異なる入口が同じレジストリと style を共有する")
    func TS_CO_06_entriesShareRegistryAndStyle() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let injected: any KsToast = Toast(coordinator: harness.coordinator)

        harness.toast.registry.register(ToastTestViewModel.self) { viewModel in
            MessageTestContentView(message: viewModel.message)
        }
        harness.toast.style = ToastStyle(
            fontSize: 20,
            defaultDuration: Self.shortDuration,
            defaultPlacement: DialogPlacement(verticalAlignment: .start)
        )

        #expect(injected.registry === harness.toast.registry, "レジストリは同じ実体")
        #expect(injected.style.fontSize == 20, "style も同じ実体から読まれる")

        try injected.show(ToastTestViewModel(message: "共有"), duration: Self.shortDuration)
        try #require(await harness.waitUntilPresenting(), "別インスタンスからも同じ登録で表示できる")
        #expect(harness.contentViews.first is MessageTestContentView)

        #expect(
            Toast().coordinator === Toast.shared.coordinator,
            "既定エントリと注入インスタンスは同じ状態の正を指す"
        )
    }

    @Test("[TS-CO-07] 受理後の factory 失敗は破棄と資源解放")
    func TS_CO_07_failureAfterAcceptanceDiscardsSingleDisplay() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        // 受理は通るが中身の実体化で失敗する登録。型消去された factory が
        // 別の ViewModel 型を待っているため、実体化の時点で nil が返る。
        harness.registry.register(
            ToastViewFactory.make(ToastTestViewModel.self) { _ in UIView() },
            forKey: DialogViewModelKey(MismatchedToastTestViewModel.self)
        )

        try harness.toast.show(MismatchedToastTestViewModel(), duration: Self.shortDuration)

        await harness.drainAcceptance()
        #expect(harness.displayCount == 0, "その表示だけが破棄され、表示リストに残らない")
        #expect(harness.attachedContainerViews.isEmpty)

        harness.toast.show(message: "後続", duration: Self.shortDuration)
        #expect(await harness.waitUntilPresenting(), "後続の show は正常に表示される")
    }

    @Test("[TS-CO-07] インライン経路の factory が投げた失敗もその表示1枚の破棄に留まる")
    func TS_CO_07_throwingInlineFactoryDiscardsSingleDisplay() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }

        // 登録を経ずに、その場で渡した中身の作り手が失敗を投げる
        try harness.toast.show(
            ToastTestViewModel(),
            duration: Self.shortDuration,
            placement: nil
        ) { _ throws -> UIView in
            throw ToastTestContentFailure.cannotMakeContent
        }

        await harness.drainAcceptance()
        #expect(harness.displayCount == 0, "その表示だけが破棄され、表示リストに残らない")
        #expect(harness.attachedContainerViews.isEmpty)

        harness.toast.show(message: "後続", duration: Self.shortDuration)
        #expect(await harness.waitUntilPresenting(), "後続の show は正常に表示される")
    }

    @Test("[TS-CO-07] 登録経路の factory が投げた失敗もその表示1枚の破棄に留まる")
    func TS_CO_07_throwingRegisteredFactoryDiscardsSingleDisplay() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        // 中身の作り手が失敗を投げる登録。互換面 (MAUI / KMP) の中身の供給元が
        // 中身を作れなかった場合はこの登録経路を通る。
        harness.registry.register(ToastTestViewModel.self) { _ throws -> UIView in
            throw ToastTestContentFailure.cannotMakeContent
        }

        try harness.toast.show(ToastTestViewModel(), duration: Self.shortDuration)

        await harness.drainAcceptance()
        #expect(harness.displayCount == 0, "その表示だけが破棄され、表示リストに残らない")
        #expect(harness.attachedContainerViews.isEmpty)

        harness.toast.show(message: "後続", duration: Self.shortDuration)
        #expect(await harness.waitUntilPresenting(), "後続の show は正常に表示される")
    }

    @Test("取り付け先が無い間は表示を保留し、現れたら表示する")
    func pendingDisplayAttachesWhenHostAppears() async throws {
        let harness = ToastTestHarness(hasHost: false)
        defer { harness.tearDown() }

        harness.toast.show(message: "提示先を待つ", duration: Self.longDuration)

        await harness.drainAcceptance()
        #expect(harness.displayCount == 1, "呼び出しは失敗せず、表示は保留される")
        #expect(harness.containers.isEmpty, "取り付け先が無い間は器を作らない")

        harness.surface.hostView = harness.window
        NotificationCenter.default.post(
            name: UIWindow.didBecomeKeyNotification,
            object: harness.window
        )

        #expect(await harness.waitUntilPresenting(), "提示先の出現で表示される")
    }

    @Test("提示先が現れないまま期限が来た表示は表示されずに破棄される")
    func pendingDisplayIsDiscardedWhenDeadlinePasses() async throws {
        let harness = ToastTestHarness(hasHost: false)
        defer { harness.tearDown() }

        harness.toast.show(message: "提示先が現れない", duration: 200)

        #expect(await harness.waitUntilEmpty(), "計時は受理時点から消費されている")
        #expect(harness.containers.isEmpty, "一度も表示されない")
    }

    @Test("期限を過ぎた保留表示は、取り付け先の復帰がタイマーより先でも表示されない")
    func expiredPendingDisplayIsNotAttachedWhenHostReturnsFirst() async throws {
        let harness = ToastTestHarness(hasHost: false)
        defer { harness.tearDown() }

        harness.toast.show(message: "期限切れ", duration: 200)
        await harness.drainAcceptance()
        try #require(harness.displayCount == 1, "取り付け先が無いので表示は保留される")

        Self.returnHostAfterDeadline(harness, waiting: 0.35)

        #expect(harness.containers.isEmpty, "期限に達した表示は器を取り付けない")
        #expect(harness.displayCount == 0, "その場で破棄される")
        #expect(
            harness.announcer.announcedMessages.isEmpty,
            "表示されない Toast の文言が読み上げへ流れている"
        )
    }

    /// 期限を越えてから、その場で取り付け先を戻す。
    ///
    /// 同期の関数にしてメインスレッドを占有したまま期限を越えるので、
    /// 期限のタイマー (MainActor 上の Task) は復帰の処理より後にしか走れない。
    @MainActor
    private static func returnHostAfterDeadline(
        _ harness: ToastTestHarness,
        waiting seconds: TimeInterval
    ) {
        harness.surface.hostView = harness.window
        Thread.sleep(forTimeInterval: seconds)
        harness.coordinator.attachPendingDisplays()
    }

    @Test("[TS-CO-08] 計時は受理時点から進み、入りの途中でも duration 到達で出へ移る")
    func TS_CO_08_deadlineOverridesUnfinishedPresentation() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let probe = DialogTransitionProbe()
        let gate = DialogTransitionGate()

        try harness.toast.show(ToastTestViewModel(), duration: 150) { _ in
            let view = FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
            // 入りの演出が完了しないまま期限を迎える状況を作る。
            view.ksDialogTransition = DialogTransition(
                presentation: probe.gatedHook(.presentation, gate: gate),
                dismissal: probe.immediateHook(.dismissal)
            )
            return view
        }

        try #require(await harness.waitUntilPresenting())
        try #require(
            await DialogTestWaiting.waitUntil { probe.callCount(.presentation) == 1 },
            "入りのフックが走り始める"
        )

        #expect(
            await harness.waitUntilEmpty(timeout: .seconds(3)),
            "入りの完了を待たずに出へ移り、撤去まで進む"
        )
        #expect(probe.callCount(.dismissal) == 1, "出のフックが呼ばれる")
        #expect(probe.hasEvent(.cancelled(.presentation)), "完了しない入りは取り消される")
        gate.open()
    }
}
#endif
