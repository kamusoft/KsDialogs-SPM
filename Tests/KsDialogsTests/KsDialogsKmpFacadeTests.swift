#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

@Suite("KMP 向け Swift 型付き公開面", .serialized)
@MainActor
struct KsDialogsKmpFacadeTests {
    private static let contentSize = CGSize(width: 280, height: 180)

    /// 期待値の導出を単純にするため、基準領域はウィンドウ全体・余白なしにする。
    private static func plainOptions() -> DialogOptions {
        DialogOptions(layoutArea: .window, dialogMargin: .zero)
    }

    /// 共有コードからの show に対応する経路。委譲面は同じレジストリと提示面を使う。
    private func sharedCodeFace(harness: DialogTestHarness) -> KsDialogsInteropBridge {
        KsDialogsInteropBridge(
            registry: harness.registry,
            presentationSurface: harness.presentationSurface
        )
    }

    @Test("型付き登録した共有 VM を共有コードから show すると型付き結果が届く")
    func typedRegistrationIsResolvedFromSharedCodeShow() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<String>()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self, result: String.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }
        let interopRecorder = DialogInteropTestRecorder()

        sharedCodeFace(harness: harness).show(SharedTestDialogViewModel(message: "確認")) { result in
            interopRecorder.record(result: result)
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try await recorder.notifier(at: 0).complete("入力")

        try #require(await DialogTestWaiting.waitUntil { interopRecorder.resultCount == 1 })
        let result = try #require(interopRecorder.firstResult)
        #expect(result.kind == .completed)
        #expect(result.value as? String == "入力", "共有コード側へ宣言結果型の値が届くこと")
        #expect(await harness.waitForPresentedContainers(count: 0))
    }

    @Test("result を省略した登録と show は真偽値になる")
    func omittedResultTypeDefaultsToBool() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "確認")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try await recorder.notifier(at: 0).complete(true)

        let result: DialogResult<Bool> = try await showTask.value
        #expect(result == .completed(true))
    }

    @Test("Swift から型付き show を await して結果を受け取る")
    func swiftTypedShowReturnsDeclaredResultType() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<String>()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self, result: String.self) { viewModel, notifier in
            recorder.recording(notifier: notifier, content: Text(viewModel.message))
        }

        let showTask = Task {
            try await harness.dialogs.kmp.show(
                SharedTestDialogViewModel(message: "確認"),
                result: String.self
            )
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try await recorder.notifier(at: 0).complete("入力")

        let result: DialogResult<String> = try await showTask.value
        #expect(result == .completed("入力"))
        #expect(await harness.waitForPresentedContainers(count: 0))
    }

    @Test("Swift の型付き show はキャンセル報告を cancelled として返す")
    func swiftTypedShowReturnsCancelled() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<String>()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self, result: String.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task {
            try await harness.dialogs.kmp.show(
                SharedTestDialogViewModel(message: "確認"),
                result: String.self
            )
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try await recorder.notifier(at: 0).cancel()

        #expect(try await showTask.value == .cancelled)
    }

    @Test("SwiftUI の中身への添付 DSL は KMP 経路でも実効値になる")
    func swiftUIAttachmentIsAppliedThroughKmpFace() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { _, notifier in
            recorder.recording(
                notifier: notifier,
                content: FixedSizeSwiftUIContent(contentSize: Self.contentSize)
                    .ksDialogOptions(Self.plainOptions())
                    .ksDialogPlacement(DialogPlacement(horizontalAlignment: .start, verticalAlignment: .end))
            )
        }

        let showTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "確認")) }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        try #require(await DialogTestWaiting.waitUntil { container.isLayoutSnapshotFrozen })
        container.view.layoutIfNeeded()

        // 提示面の 390 × 844 に対し、水平は Start、垂直は End。
        DialogRectExpectation.expect(
            container.contentView.frame,
            equals: CGRect(x: 0, y: 664, width: 280, height: 180)
        )

        try await recorder.notifier(at: 0).complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    @Test("共有コードの show 引数 placement は添付 DSL より優先される")
    func sharedCodeShowPlacementOverridesAttachment() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { _, notifier in
            recorder.recording(
                notifier: notifier,
                content: FixedSizeSwiftUIContent(contentSize: Self.contentSize)
                    .ksDialogOptions(Self.plainOptions())
                    .ksDialogPlacement(DialogPlacement(horizontalAlignment: .start, verticalAlignment: .start))
            )
        }
        let interopRecorder = DialogInteropTestRecorder()

        sharedCodeFace(harness: harness).show(
            SharedTestDialogViewModel(message: "確認"),
            placement: KsDialogsInteropPlacement(
                horizontalAlignment: .start,
                verticalAlignment: .end,
                offsetX: 10,
                offsetY: 0
            )
        ) { result in
            interopRecorder.record(result: result)
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        try #require(await DialogTestWaiting.waitUntil { container.isLayoutSnapshotFrozen })
        container.view.layoutIfNeeded()

        // 添付は Start / Start だが、show 引数の Start + Offset 10 / End がまるごと置換する。
        DialogRectExpectation.expect(
            container.contentView.frame,
            equals: CGRect(x: 10, y: 664, width: 280, height: 180)
        )

        try await recorder.notifier(at: 0).complete(true)
        try #require(await DialogTestWaiting.waitUntil { interopRecorder.resultCount == 1 })
    }

    @Test("show で指定した結果型と合わない結果は型付きエラーになる")
    func showRejectsResultOfUndeclaredType() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { _, notifier in
            let view = DialogTestContentView()
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task {
            try await harness.dialogs.kmp.show(
                SharedTestDialogViewModel(message: "確認"),
                result: String.self
            )
        }
        try #require(await harness.waitForPresentedContainers(count: 1))
        try await recorder.notifier(at: 0).complete(true)

        await #expect(throws: KsDialogsKmpError.resultTypeMismatch(expected: "String", actual: "Bool")) {
            try await showTask.value
        }
        #expect(await harness.waitForPresentedContainers(count: 0), "型不一致でもダイアログは閉じること")
    }

    @Test("登録時の宣言結果型と合わない報告も、内部の印を見せずに型付きエラーになる")
    func showSurfacesRegistrationResultTypeMismatchAsTypedError() async throws {
        let harness = DialogTestHarness()
        let interopRecorder = DialogInteropTestRecorder()
        // 宣言結果型を Boolean として登録した委譲面の紐付けに対し、文字列を報告させる。
        sharedCodeFace(harness: harness).registerViewFactory(
            forViewModelClass: InteropTestDialogViewModel.self,
            resultType: KsDialogsInteropResultType(name: "Bool") { $0 is Bool }
        ) { _, notifier in
            interopRecorder.record(notifier: notifier)
            return DialogTestContentView()
        }

        let showTask = Task { try await harness.dialogs.kmp.show(InteropTestDialogViewModel(message: "確認")) }
        try #require(await DialogTestWaiting.waitUntil { interopRecorder.notifierCount == 1 })
        interopRecorder.notifier(at: 0)?.complete("文字列")

        await #expect(throws: KsDialogsKmpError.resultTypeMismatch(expected: "Bool", actual: "String")) {
            try await showTask.value
        }
    }

    @Test("未登録の共有 VM の show は結果を返さずに型付きエラーになる")
    func showRejectsUnregisteredViewModel() async throws {
        let harness = DialogTestHarness()

        await #expect(
            throws: KsDialogsKmpError.notRegistered(viewModelType: "SharedTestDialogViewModel")
        ) {
            try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "確認"))
        }
        #expect(harness.presentedContainers.isEmpty)
    }

    @Test("提示先が無いときの show は失敗せずに待ち、打ち切ると cancelled で終わる")
    func showWaitsForMissingPresentationHostUntilCancelled() async throws {
        let harness = DialogTestHarness(hasPresentationHost: false)
        let supply = DialogTestCallCounter()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { _, _ in
            supply.increment()
            return DialogTestContentView()
        }

        let showTask = Task { try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "確認")) }
        try #require(
            await DialogTestWaiting.waitUntil { harness.presentationSurface.hostWaitQueue.waitingCount == 1 },
            "登録済みの共有 VM の show は、失敗せずに提示先を待つ"
        )

        showTask.cancel()

        #expect(try await showTask.value == .cancelled, "待っている間の打ち切りは cancelled で終わる")
        #expect(supply.count == 0, "一度も中身を作らない")
        #expect(harness.presentationSurface.hostWaitQueue.waitingCount == 0)
    }

    /// 共有コードからの show に対応する経路へ、中身に ViewModel の message を識別子として付ける登録をする。
    private static func registerIdentifiedContent(in harness: DialogTestHarness) {
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { viewModel, _ in
            let view = DialogTestContentView()
            view.accessibilityIdentifier = viewModel.message
            return view
        }
    }

    /// 下から順に並んだ、表示中のダイアログの中身の識別子 (ViewModel の message)。
    private static func presentedMessages(in harness: DialogTestHarness) -> [String?] {
        harness.presentedContainers.map { $0.contentView.accessibilityIdentifier }
    }

    @Test("[PB-HW-06] 共有コードから続けて呼んだ show は、呼び出しから戻った時点で呼んだ順に列に並ぶ")
    func PB_HW_06_sharedCodeShowsQueueInCallOrderOnReturn() async throws {
        let harness = DialogTestHarness(hasPresentationHost: false)
        Self.registerIdentifiedContent(in: harness)
        let face = sharedCodeFace(harness: harness)
        let results = DialogInteropTestRecorder()

        // UI スレッドから、間に待ち合わせを挟まずに A、B の順で呼ぶ。
        let showA = face.show(SharedTestDialogViewModel(message: "A")) { results.record(result: $0) }
        let showB = face.show(SharedTestDialogViewModel(message: "B")) { results.record(result: $0) }
        #expect(
            harness.presentationSurface.hostWaitQueue.waitingCount == 2,
            "表示の処理が UI スレッドで始まるのを待たずに、呼び出しの時点で 2 件とも列に並んでいる"
        )

        harness.presentationSurface.isPresentationHostAvailable = true
        harness.presentationSurface.fireHostAppearance()

        try #require(await harness.waitForPresentedContainers(count: 2), "2 枚とも表示される")
        #expect(Self.presentedMessages(in: harness) == ["A", "B"], "呼んだ順に表示され、B が A の手前に重なる")

        showB.cancel()
        showA.cancel()
        try #require(await DialogTestWaiting.waitUntil { results.resultCount == 2 })
        #expect(harness.presentationSurface.hostWaitQueue.waitingCount == 0)
    }

    @Test("共有コードの show も、提示先があって待っているものが無ければ前の提示の完了を待たずに表示する")
    func sharedCodeShowWithHostAndEmptyQueuePresentsImmediately() async throws {
        let harness = DialogTestHarness()
        Self.registerIdentifiedContent(in: harness)
        let face = sharedCodeFace(harness: harness)
        let results = DialogInteropTestRecorder()
        // 提示の完了を知らせない状態でも、列を通らない show は互いを待たない。
        harness.presentationSurface.holdsPresentationCompletion = true

        let showA = face.show(SharedTestDialogViewModel(message: "A")) { results.record(result: $0) }
        let showB = face.show(SharedTestDialogViewModel(message: "B")) { results.record(result: $0) }

        try #require(await harness.waitForPresentedContainers(count: 2), "A の提示の完了を待たずに B も表示される")
        #expect(Self.presentedMessages(in: harness) == ["A", "B"])
        #expect(harness.presentationSurface.hostWaitQueue.waitingCount == 0, "列には並ばない")

        harness.presentationSurface.completeHeldPresentations()
        showB.cancel()
        showA.cancel()
        try #require(await DialogTestWaiting.waitUntil { results.resultCount == 2 })
    }

    @Test("共有コードの show が列に着かずに失敗しても、後から呼んだ show は止まらない")
    func sharedCodeShowFailingBeforeQueueDoesNotBlockLaterShow() async throws {
        let harness = DialogTestHarness(hasPresentationHost: false)
        Self.registerIdentifiedContent(in: harness)
        let face = sharedCodeFace(harness: harness)
        let failure = DialogInteropTestRecorder()
        let results = DialogInteropTestRecorder()

        // 未登録の ViewModel の show は、札を取ったあと列に着く前に失敗する。
        face.show(UnregisteredTestDialogViewModel()) { failure.record(result: $0) }
        let showA = face.show(SharedTestDialogViewModel(message: "A")) { results.record(result: $0) }

        try #require(await DialogTestWaiting.waitUntil { failure.resultCount == 1 })
        #expect(failure.firstResult?.kind == .error, "未登録は失敗として返る")
        try #require(
            await DialogTestWaiting.waitUntil { harness.presentationSurface.hostWaitQueue.waitingCount == 1 },
            "失敗した show の札は手放され、A だけが待っている"
        )

        harness.presentationSurface.isPresentationHostAvailable = true
        harness.presentationSurface.fireHostAppearance()
        try #require(await harness.waitForPresentedContainers(count: 1), "A は失敗した show に止められずに表示される")
        #expect(Self.presentedMessages(in: harness) == ["A"])

        showA.cancel()
        try #require(await DialogTestWaiting.waitUntil { results.resultCount == 1 })
    }

    @Test("理由の欠けた失敗は、提示先の不在ではなく理由が欠けていたことを表す失敗になる")
    func missingFailureReasonIsReportedAsItself() {
        let error = KsDialogsKmpError.publicError(from: nil)

        #expect(error as? KsDialogsKmpMissingFailureReason == KsDialogsKmpMissingFailureReason())
        #expect(error.localizedDescription == "The Dialog failed without a reported reason.")
    }

    @Test("型付き公開面の登録は iOS Native の登録と同じレジストリに載る")
    func typedRegistrationSharesTheNativeRegistry() async throws {
        let harness = DialogTestHarness()
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self) { _, _ in DialogTestContentView() }

        let key = DialogViewModelKey(SharedTestDialogViewModel.self)
        #expect(harness.registry.factory(forKey: key) != nil)
    }
}
#endif
