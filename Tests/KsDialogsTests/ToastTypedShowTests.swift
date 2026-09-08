#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// Toast の ViewModel の型を渡す表示 (core/ADR-0035) を確かめる。
///
/// ViewModel はレジストリの ViewModel factory が作り、実行順序は
/// 「ViewModel 生成 → configure 完了 → 中身の生成 → 表示」で固定される。
/// ViewModel factory 未登録だけが呼び出し時点の同期の失敗で、生成と configure の失敗は
/// 受理後の失敗 (その表示1枚だけの破棄) に分類される。
@Suite("Toast の ViewModel の型を渡す表示", .serialized)
@MainActor
struct ToastTypedShowTests {
    private static let contentSize = CGSize(width: 200, height: 60)

    /// 表示が消える前後を見分けるために使う短い duration。
    private static let shortDuration = 400

    /// 観察の途中で期限が来ないだけの長さ。
    private static let longDuration = 5000

    /// configure が投げる、テスト専用の失敗。
    struct ConfigureFailure: Error, Equatable {}

    /// 未登録の型として観察するときに使う名前。
    private static var configurableViewModelTypeName: String {
        String(describing: ConfigurableToastTestViewModel.self)
    }

    /// ViewModel factory と View factory の両スロットを登録する。
    private static func registerBothSlots(
        in harness: ToastTestHarness,
        recorder: ToastTypedShowRecorder,
        factoryTitle: String = "factory の既定"
    ) {
        harness.registry.register(ConfigurableToastTestViewModel.self) {
            let viewModel = ConfigurableToastTestViewModel(title: factoryTitle)
            recorder.recordCreation(viewModel)
            return viewModel
        }
        registerViewFactory(in: harness, recorder: recorder)
    }

    /// View factory のスロットだけを登録する。
    private static func registerViewFactory(
        in harness: ToastTestHarness,
        recorder: ToastTypedShowRecorder
    ) {
        harness.registry.register(ConfigurableToastTestViewModel.self) { viewModel in
            recorder.recordContent(title: viewModel.title)
            return FixedContentSizeView(contentSize: Self.contentSize)
        }
    }

    // MARK: - レジストリの2スロット

    @Test("[TS-TY-01] VM factory の再登録は View factory を保持する")
    func TS_TY_01_reregistrationReplacesOnlyTheTargetSlot() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let first = ToastTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: first)

        // ViewModel factory だけを登録し直す。View factory のスロットは触らない。
        harness.registry.register(ConfigurableToastTestViewModel.self) {
            ConfigurableToastTestViewModel(title: "新しい VM factory")
        }
        try harness.toast.show(ConfigurableToastTestViewModel.self, duration: Self.longDuration)
        await harness.drainAcceptance()

        #expect(first.observedTitles == ["新しい VM factory"], "新しい VM factory の生成物が使われる")
        #expect(harness.contentViews.first is FixedContentSizeView, "View factory は登録時のものが保持される")

        // 逆に View factory だけを登録し直しても ViewModel factory は保持される。
        let second = ToastTypedShowRecorder()
        Self.registerViewFactory(in: harness, recorder: second)
        try harness.toast.show(ConfigurableToastTestViewModel.self, duration: Self.longDuration)
        await harness.drainAcceptance()

        #expect(second.observedTitles == ["新しい VM factory"], "VM factory は保持される")
        #expect(first.creationCount == 1, "古い View factory は使われない")
    }

    // MARK: - 型指定 show

    @Test("[TS-TY-02] 型指定 show が生成 → configure → 表示の一連で動く")
    func TS_TY_02_typedShowCreatesConfiguresAndPresents() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        try harness.toast.show(
            ConfigurableToastTestViewModel.self,
            duration: Self.shortDuration
        ) { viewModel in
            viewModel.title = "configure で設定"
        }

        try #require(await harness.waitUntilPresenting())
        #expect(recorder.createdViewModels.count == 1, "VM factory の生成物が使われる")
        #expect(recorder.observedTitles == ["configure で設定"], "configure の設定を中身の生成が読める")
        let contentView = try #require(harness.contentViews.first)
        #expect(contentView is FixedContentSizeView)

        #expect(await harness.waitUntilEmpty(), "duration の経過で消える")
        #expect(contentView.window == nil)
    }

    @Test("[TS-TY-03] VM factory 未登録の型指定 show は呼び出し時点で失敗する")
    func TS_TY_03_typedShowWithoutViewModelFactoryFailsSynchronously() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        Self.registerViewFactory(in: harness, recorder: recorder)

        #expect(throws: DialogError.viewModelFactoryNotRegistered(
            viewModelType: Self.configurableViewModelTypeName)) {
            try harness.toast.show(ConfigurableToastTestViewModel.self, duration: Self.longDuration)
        }

        await harness.drainAcceptance()
        #expect(recorder.creationCount == 0)
        #expect(harness.displayCount == 0, "表示は行われない")
    }

    @Test("[TS-TY-04] configure の失敗は受理後の失敗としてその1枚だけを破棄する")
    func TS_TY_04_configureFailureDiscardsSingleDisplay() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        // 別の表示を先に出しておく。
        harness.toast.show(message: "先の表示", duration: Self.longDuration)
        try #require(await harness.waitUntilPresenting(count: 1))

        // 失敗は呼び出し元へ返らない (呼び出しは同期に戻る)。
        try harness.toast.show(
            ConfigurableToastTestViewModel.self,
            duration: Self.longDuration
        ) { _ in
            throw ConfigureFailure()
        }
        await harness.drainAcceptance()

        #expect(recorder.creationCount == 0, "View factory は呼ばれない")
        #expect(harness.displayCount == 1, "その1枚だけが破棄され、表示中の別の Toast は残る")

        harness.toast.show(message: "後続", duration: Self.longDuration)
        #expect(await harness.waitUntilPresenting(count: 2), "後続の show は正常に表示される")
    }

    @Test("[TS-TY-05] configure 省略の型指定 show は VM factory の生成物をそのまま表示する")
    func TS_TY_05_typedShowWithoutConfigurePresentsFactoryOutputAsIs() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        try harness.toast.show(ConfigurableToastTestViewModel.self, duration: Self.longDuration)

        try #require(await harness.waitUntilPresenting())
        #expect(recorder.observedTitles == ["factory の既定"])
    }

    @Test("[TS-TY-06] 型指定 show でも duration と置き場所の引数が効く")
    func TS_TY_06_durationAndPlacementArgumentsApply() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: recorder)

        try harness.toast.show(
            ConfigurableToastTestViewModel.self,
            duration: Self.shortDuration,
            placement: DialogPlacement(verticalAlignment: .start)
        )

        try #require(await harness.waitUntilPresenting())
        harness.window.layoutIfNeeded()
        let placedFrame = try #require(harness.contentViews.first).frame
        #expect(
            abs(placedFrame.minY - (ToastTestHarness.portraitInsets.top + 24)) <= 1,
            "引数の配置がインスタンス渡し show と同じ規則で効く (実測 \(placedFrame))"
        )

        #expect(await harness.waitUntilEmpty(), "指定した duration の経過で消える")
    }

    @Test("[TS-TY-07] 型指定 show は呼び出し時点のエントリで View まで作る")
    func TS_TY_07_typedShowUsesEntrySnapshotTakenAtCall() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let first = ToastTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: first, factoryTitle: "最初の VM")

        // 受理の待ち行列を止めて、UI スレッドでの処理が始まる前に再登録できるようにする。
        let gate = DialogTransitionGate()
        harness.coordinator.acceptanceQueue.enqueue { try? await gate.wait() }

        try harness.toast.show(ConfigurableToastTestViewModel.self, duration: Self.longDuration)

        let second = ToastTypedShowRecorder()
        Self.registerBothSlots(in: harness, recorder: second, factoryTitle: "後の VM")

        gate.open()
        await harness.drainAcceptance()

        #expect(first.observedTitles == ["最初の VM"], "最初に取得した VM factory と View factory の組で表示される")
        #expect(second.createdViewModels.isEmpty, "再登録後の VM factory は使われない")
        #expect(second.creationCount == 0, "再登録後の View factory は使われない")
        #expect(await harness.waitUntilPresenting())
    }

    // MARK: - 呼び出しコンテキスト

    @Test("[TS-TY-09] 型指定 show は任意スレッドから呼べ、VM factory と configure は UI スレッドで実行される")
    func TS_TY_09_typedShowIsCallableFromAnyThread() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        harness.registry.register(ConfigurableToastTestViewModel.self) {
            #expect(DialogTestThread.isMainThread(), "VM factory は UI スレッドで実行される")
            let viewModel = ConfigurableToastTestViewModel()
            recorder.recordCreation(viewModel)
            return viewModel
        }
        Self.registerViewFactory(in: harness, recorder: recorder)
        let toast = harness.toast
        let duration = Self.longDuration

        let calledOffMainThread = try await Task.detached { () -> Bool in
            let isOffMainThread = !DialogTestThread.isMainThread()
            try toast.show(
                ConfigurableToastTestViewModel.self,
                duration: duration
            ) { viewModel in
                #expect(DialogTestThread.isMainThread(), "configure は UI スレッドで実行される")
                viewModel.title = "背面スレッドからの表示"
            }
            return isOffMainThread
        }.value

        #expect(calledOffMainThread, "呼び出しは UI スレッド外から同期に戻る")
        try #require(await harness.waitUntilPresenting())
        #expect(recorder.observedTitles == ["背面スレッドからの表示"])
    }

    // MARK: - 宣言的 UI 系の登録

    @Test("[TS-YI-02] SwiftUI 登録でも Toast の型指定 show が同じに働く")
    func TS_YI_02_swiftUIRegistrationSupportsTypedShow() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let recorder = ToastTypedShowRecorder()
        harness.registry.register(ConfigurableToastTestViewModel.self) {
            ConfigurableToastTestViewModel(title: "SwiftUI の既定")
        }
        harness.registry.register(ConfigurableToastTestViewModel.self) { viewModel in
            recorder.recordContent(title: viewModel.title)
            return Text(viewModel.title)
                .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        }

        try harness.toast.show(
            ConfigurableToastTestViewModel.self,
            duration: Self.longDuration
        ) { viewModel in
            viewModel.title = "SwiftUI の configure"
        }

        try #require(await harness.waitUntilPresenting())
        #expect(recorder.observedTitles == ["SwiftUI の configure"], "configure の設定が表示へ反映される")
        #expect(harness.containers.first?.contentHost != nil, "ホストごと器に組み込まれる")
    }
}
#endif
