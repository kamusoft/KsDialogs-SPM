#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Toast の公開面と fire-and-forget の契約 (core/ADR-0028・0029・0031) を確かめる。
///
/// show は戻り値を持たず、消滅の契機は duration の経過だけである。
/// 構成ミス (未登録の ViewModel 型) だけが呼び出し時点の失敗になり、
/// 受理した後の失敗はその表示1枚の破棄に留まる。
///
/// 表示時間は、背面で受理した表示なら受理の時点から、前面にいるのに提示先が無い間 (前面の待ち) に
/// 受理した表示なら提示先に載った時点か背面へ下がった時点から数える (core/ADR-0043)。
@Suite("Toast の公開面と fire-and-forget", .serialized, .awaitsMainActorResponsive)
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

    // MARK: - 提示先の出現待ち

    @Test("[TS-HW-01] 背面で受理された Toast は、提示先が現れた時点で表示され、受理時点から数えた duration で消える")
    func TS_HW_01_backgroundAcceptedDisplayIsAttachedWhenHostAppears() async throws {
        let harness = ToastTestHarness(hasHost: false, isAppInForeground: false)
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        let probe = DialogTransitionProbe()
        let acceptedAt = ContinuousClock.now

        // 出入りの演出を即座に終えるので、表示が消える時点がそのまま期限の到達になる。
        try harness.toast.show(ConfigurableToastTestViewModel(), duration: Self.hostWaitDuration) { viewModel in
            recorder.recordContent(title: viewModel.title)
            let view = FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
            view.ksDialogTransition = DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.immediateHook(.dismissal)
            )
            return view
        }

        await harness.drainAcceptance()
        #expect(harness.displayCount == 1, "呼び出しは失敗せず、表示は保留される")
        try await Task.sleep(for: Self.hostlessPeriod)
        #expect(recorder.creationCount == 0, "提示先が無い間は View factory が呼ばれない")
        #expect(harness.containers.isEmpty, "提示先が無い間は器を作らない")

        harness.surface.returnHost(harness.window)

        #expect(recorder.creationCount == 1, "提示先が現れた時点で中身が作られる")
        #expect(await harness.waitUntilPresenting(), "提示先の出現で表示される")
        #expect(await harness.waitUntilEmpty(), "duration の到達で消える")
        let elapsed = acceptedAt.duration(to: .now)
        #expect(
            elapsed < Self.hostlessPeriod + .milliseconds(Self.hostWaitDuration),
            "計時は受理時点から数える (提示先が現れた時点から数え直さない): \(elapsed)"
        )
        #expect(probe.callCount(.presentation) == 1, "入りの演出から表示される")
    }

    @Test("[TS-HW-02] 提示先が現れないまま満了した Toast は、中身が作られずに破棄される")
    func TS_HW_02_expiredPendingDisplayCreatesNothing() async throws {
        // 背面で受理するので、提示先が無い間も期限へ向けて時間が進む。
        let harness = ToastTestHarness(hasHost: false, isAppInForeground: false)
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        let configureCounter = DialogTestCallCounter()
        harness.registry.register(ConfigurableToastTestViewModel.self) {
            let viewModel = ConfigurableToastTestViewModel()
            recorder.recordCreation(viewModel)
            return viewModel
        }
        harness.registry.register(ConfigurableToastTestViewModel.self) { viewModel in
            recorder.recordContent(title: viewModel.title)
            return FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
        }

        try harness.toast.show(ConfigurableToastTestViewModel.self, duration: 200) { _ in
            configureCounter.increment()
        }

        await harness.drainAcceptance()
        #expect(harness.displayCount == 1, "呼び出しは失敗せず、表示は保留される")
        #expect(await harness.waitUntilEmpty(), "計時は受理時点から消費され、満了で表示リストから外れる")
        #expect(harness.containers.isEmpty, "一度も表示されない")
        #expect(recorder.createdViewModels.isEmpty, "VM factory は呼ばれない")
        #expect(configureCounter.count == 0, "configure は呼ばれない")
        #expect(recorder.creationCount == 0, "View factory は呼ばれない")
        #expect(harness.surface.hostAppearance.activeRegistrationCount == 0, "待ちの購読は解除される")
    }

    @Test("[TS-HW-03] 期限を過ぎた保留表示は、提示先の出現が期限の処理より先でも表示されない")
    func TS_HW_03_expiredPendingDisplayIsNotAttachedWhenHostAppearsFirst() async throws {
        let harness = ToastTestHarness(hasHost: false, isAppInForeground: false)
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()

        harness.toast.show(message: "期限切れ", duration: 200)
        try harness.toast.show(ConfigurableToastTestViewModel(), duration: 200) { viewModel in
            recorder.recordContent(title: viewModel.title)
            return FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
        }
        await harness.drainAcceptance()
        try #require(harness.displayCount == 2, "取り付け先が無いので表示は保留される")

        Self.returnHostAfterDeadline(harness, waiting: 0.35)

        #expect(harness.containers.isEmpty, "期限に達した表示は器を取り付けない")
        #expect(harness.displayCount == 0, "その場で破棄される")
        #expect(recorder.creationCount == 0, "中身も作られない")
        #expect(
            harness.announcer.announcedMessages.isEmpty,
            "表示されない Toast の文言が読み上げへ流れている"
        )
    }

    @Test("提示先を待っている間に View factory を登録し直しても、受理の時点の登録で表示される")
    func pendingRegisteredDisplayUsesFactoryResolvedAtAcceptance() async throws {
        let harness = ToastTestHarness(hasHost: false)
        defer { harness.tearDown() }
        let acceptedFactoryCalls = DialogTestCallCounter()
        let reregisteredFactoryCalls = DialogTestCallCounter()
        harness.registry.register(ToastTestViewModel.self) { _ in
            acceptedFactoryCalls.increment()
            return FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
        }

        try harness.toast.show(ToastTestViewModel(), duration: Self.hostWaitDuration)
        await harness.drainAcceptance()
        try #require(harness.displayCount == 1, "提示先が無いので表示は保留される")

        // 受理の後、提示先が現れる前に同じ ViewModel 型の登録を置き換える。
        harness.registry.register(ToastTestViewModel.self) { _ in
            reregisteredFactoryCalls.increment()
            return FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
        }
        harness.surface.hostView = harness.window
        harness.surface.fireHostAppearance()

        #expect(await harness.waitUntilPresenting(), "提示先の出現で表示される")
        #expect(acceptedFactoryCalls.count == 1, "受理の時点で登録されていた factory で中身が作られる")
        #expect(reregisteredFactoryCalls.count == 0, "受理の後に登録し直した factory は使われない")
    }

    // MARK: - 前面の待ち

    @Test("[TS-HW-04] 前面の待ちの間に受理された Toast は、duration より長く待っても破棄されず、載った時点から数えた duration で消える")
    func TS_HW_04_foregroundWaitDisplayCountsFromAttachment() async throws {
        let harness = ToastTestHarness(hasHost: false, isAppInForeground: true)
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()

        try Self.showImmediateContent(harness, recorder: recorder, duration: Self.foregroundWaitDuration)
        await harness.drainAcceptance()
        #expect(harness.displayCount == 1, "提示先が無くても受理は成立する")

        // duration より長く提示先が無いまま置く。
        try await Task.sleep(for: .milliseconds(Self.foregroundWaitDuration) + Self.overDurationWait)
        #expect(harness.displayCount == 1, "duration より長く待っても破棄されない")
        #expect(harness.containers.isEmpty, "まだ器は取り付かない")
        #expect(recorder.creationCount == 0, "待っている間は View factory が呼ばれない")

        let appearedAt = ContinuousClock.now
        harness.surface.returnHost(harness.window)

        #expect(recorder.creationCount == 1, "提示先が現れた時点で中身が作られる")
        #expect(await harness.waitUntilPresenting(), "提示先の出現で表示される")
        #expect(await harness.waitUntilEmpty())
        let elapsed = appearedAt.duration(to: .now)
        #expect(
            elapsed >= .milliseconds(Self.foregroundWaitDuration)
                && elapsed < .milliseconds(Self.foregroundWaitDuration) + Self.deadlineAllowance,
            "載った時点から数えた duration の到達で消える (載ってから \(elapsed))"
        )
    }

    @Test("[TS-HW-05] 前面の待ちのまま背面へ下がった Toast は、下がった時点から数え始める")
    func TS_HW_05_foregroundWaitDisplayCountsFromDeparture() async throws {
        let harness = ToastTestHarness(hasHost: false, isAppInForeground: true)
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()

        try Self.showImmediateContent(harness, recorder: recorder, duration: Self.foregroundWaitDuration)
        await harness.drainAcceptance()
        try #require(harness.displayCount == 1)

        try await Task.sleep(for: .milliseconds(Self.foregroundWaitDuration) + Self.overDurationWait)
        #expect(harness.displayCount == 1, "背面へ下がるまでは破棄されない")

        let leftAt = ContinuousClock.now
        harness.surface.leaveForeground()
        #expect(harness.displayCount == 1, "下がった直後はまだ破棄されない")

        #expect(await harness.waitUntilEmpty())
        let elapsed = leftAt.duration(to: .now)
        #expect(
            elapsed >= .milliseconds(Self.foregroundWaitDuration)
                && elapsed < .milliseconds(Self.foregroundWaitDuration) + Self.deadlineAllowance,
            "下がった時点から数えた duration の到達で破棄される (下がってから \(elapsed))"
        )
        #expect(harness.containers.isEmpty, "一度も表示されない")
        #expect(recorder.creationCount == 0, "中身は一度も作られない")
        #expect(harness.surface.hostAppearance.activeRegistrationCount == 0, "提示先の出現の購読は解除される")
        #expect(harness.surface.foregroundDeparture.activeRegistrationCount == 0, "前面を離れた合図の購読は解除される")
    }

    @Test("[TS-HW-06] 背面へ下がった後、期限の前に提示先が現れたら、下がった時点から数えた期限まで表示される")
    func TS_HW_06_departedDisplayShowsUntilDeadlineFromDeparture() async throws {
        let harness = ToastTestHarness(hasHost: false, isAppInForeground: true)
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()

        try Self.showImmediateContent(harness, recorder: recorder, duration: Self.foregroundWaitDuration)
        await harness.drainAcceptance()
        try #require(harness.displayCount == 1)
        try await Task.sleep(for: .milliseconds(Self.foregroundWaitDuration) + Self.overDurationWait)

        let leftAt = ContinuousClock.now
        harness.surface.leaveForeground()

        // 下がってから duration に達する前に、前面へ戻って提示先が現れる。
        try await Task.sleep(for: Self.backgroundStay)
        harness.surface.returnHost(harness.window)

        #expect(recorder.creationCount == 1, "提示先が現れた時点で中身が作られる")
        #expect(await harness.waitUntilPresenting(), "提示先が現れた時点で表示される")
        #expect(await harness.waitUntilEmpty())
        let elapsed = leftAt.duration(to: .now)
        // 載った時点から数え直していれば、下がってから backgroundStay + duration より後に消える。
        #expect(
            elapsed >= .milliseconds(Self.foregroundWaitDuration)
                && elapsed < .milliseconds(Self.foregroundWaitDuration) + Self.backgroundStay,
            "背面へ下がった時点から数えた duration の到達で消える (下がってから \(elapsed))"
        )
    }

    /// 出入りの演出を待たずに進む中身で、カスタム Toast を表示する。
    ///
    /// 撤去が期限の到達の直後に終わるので、表示リストが空になった時点を期限の到達として読める。
    private static func showImmediateContent(
        _ harness: ToastTestHarness,
        recorder: ToastTypedShowRecorder,
        duration: Int
    ) throws {
        let probe = DialogTransitionProbe()
        try harness.toast.show(ConfigurableToastTestViewModel(), duration: duration) { viewModel in
            recorder.recordContent(title: viewModel.title)
            let view = FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
            view.ksDialogTransition = DialogTransition(
                presentation: probe.immediateHook(.presentation),
                dismissal: probe.immediateHook(.dismissal)
            )
            return view
        }
    }

    /// 前面の待ちを確かめる duration (ミリ秒)。
    private static let foregroundWaitDuration = 1500

    /// 前面の待ちで、duration を明らかに超えたと言えるまで余分に置く時間。
    private static let overDurationWait = Duration.milliseconds(1000)

    /// 背面へ下がってから提示先を出すまでの時間。duration より短い。
    private static let backgroundStay = Duration.milliseconds(1000)

    /// 期限の到達から表示リストが空になるまでの遅れとして許す幅。
    private static let deadlineAllowance = Duration.milliseconds(1000)

    /// 提示先の出現待ちの観察に使う duration。
    private static let hostWaitDuration = 1200

    /// 提示先が無いまま置いておく時間。
    private static let hostlessPeriod = Duration.milliseconds(600)

    /// 期限を越えてから、その場で取り付け先を戻して提示先の出現の合図を送る。
    ///
    /// 同期の関数にしてメインスレッドを占有したまま期限を越えるので、
    /// 期限のタイマー (MainActor 上の Task) は合図の処理より後にしか走れない。
    @MainActor
    private static func returnHostAfterDeadline(
        _ harness: ToastTestHarness,
        waiting seconds: TimeInterval
    ) {
        harness.surface.hostView = harness.window
        harness.surface.isAppInForeground = true
        Thread.sleep(forTimeInterval: seconds)
        harness.surface.fireHostAppearance()
    }

    @Test("[TS-CO-08] 計時は受理時点から進み、入りの途中でも duration 到達で出へ移る")
    func TS_CO_08_deadlineOverridesUnfinishedPresentation() async throws {
        // 提示先がある状態で受理するので、計時は受理の時点から進む。
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
