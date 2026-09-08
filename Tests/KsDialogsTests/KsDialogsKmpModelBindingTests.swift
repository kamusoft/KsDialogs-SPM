#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("KMP 面の共有 VM への結果報告口の供給", .serialized)
@MainActor
struct KsDialogsKmpModelBindingTests {
    /// 共有コードからの show に対応する経路。委譲面は同じレジストリと提示面を使う。
    private func sharedCodeFace(harness: DialogTestHarness) -> KsDialogsInteropBridge {
        KsDialogsInteropBridge(
            registry: harness.registry,
            presentationSurface: harness.presentationSurface
        )
    }

    @Test("[MB-KM-01] 1引数 factory の中身が KMP 面アクセサの報告口で結果を返す")
    func viewModelOnlyFactoryReportsThroughKmpAccessor() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let recorder = KmpModelBindingTestRecorder<String>()
        kmp.register(SharedTestDialogViewModel.self, result: String.self) { viewModel in
            // 中身の生成中に引けることが要件。生成後に紐付ける実装ではここが nil になる。
            recorder.recording(
                KmpModelBindingTestContentView(
                    notifier: try? kmp.notifier(for: viewModel, result: String.self)
                )
            )
        }
        let interopRecorder = DialogInteropTestRecorder()

        sharedCodeFace(harness: harness).show(SharedTestDialogViewModel(message: "確認")) { result in
            interopRecorder.record(result: result)
        }
        let createdView = try await recorder.view(at: 0)

        let notifier = try #require(createdView.notifier, "中身の生成中に報告口が引けること")
        try #require(await harness.waitForPresentedContainers(count: 1))
        notifier.complete("入力")

        try #require(await DialogTestWaiting.waitUntil { interopRecorder.resultCount == 1 })
        let result = try #require(interopRecorder.firstResult)
        #expect(result.kind == .completed)
        #expect(result.value as? String == "入力", "共有コード側へ宣言結果型の値が届くこと")
        #expect(await harness.waitForPresentedContainers(count: 0))
    }

    @Test("[MB-KM-04] 登録時の結果型と違う型の指定は空ではなく型付きの失敗になる")
    func accessorRejectsMismatchedResultType() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let recorder = KmpModelBindingTestRecorder<String>()
        kmp.register(SharedTestDialogViewModel.self, result: String.self) { viewModel in
            recorder.recording(
                KmpModelBindingTestContentView(
                    notifier: try? kmp.notifier(for: viewModel, result: String.self)
                )
            )
        }

        let viewModel = SharedTestDialogViewModel(message: "確認")
        #expect(try kmp.notifier(for: viewModel, result: String.self) == nil, "show 前は空になること")

        let showTask = Task { try await kmp.show(viewModel, result: String.self) }
        _ = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        // 結果型を省略した (= 真偽値を指定した) 取り出しは、空ではなく型の食い違いとして失敗する。
        #expect(throws: KsDialogsKmpError.resultTypeMismatch(expected: "Bool", actual: "String")) {
            _ = try kmp.notifier(for: viewModel)
        }

        // 同じ表示中の VM でも、登録時の結果型で指定すれば報告口が引ける。
        let notifier = try #require(try kmp.notifier(for: viewModel, result: String.self))
        notifier.complete("入力")

        #expect(try await showTask.value == .completed("入力"))
    }

    @Test("[MB-KM-04] 表示中の再登録は出ているダイアログの結果型判定を変えない")
    func accessorUsesShowTimeResultTypeAfterReregistration() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let recorder = KmpModelBindingTestRecorder<String>()
        kmp.register(SharedTestDialogViewModel.self, result: String.self) { viewModel in
            recorder.recording(
                KmpModelBindingTestContentView(
                    notifier: try? kmp.notifier(for: viewModel, result: String.self)
                )
            )
        }

        let viewModel = SharedTestDialogViewModel(message: "確認")
        let showTask = Task { try await kmp.show(viewModel, result: String.self) }
        _ = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        // 表示したまま、同じ共有 VM 型を別の結果型で登録し直す。
        kmp.register(SharedTestDialogViewModel.self, result: Int.self) { _ in
            KmpModelBindingTestContentView<Int>(notifier: nil)
        }

        // 出ているダイアログの報告口は、show を始めた時点の結果型で引ける。
        let notifier = try #require(try kmp.notifier(for: viewModel, result: String.self))
        // あとから登録された結果型を指定しても、この表示の型とは食い違うので失敗になる。
        #expect(throws: KsDialogsKmpError.resultTypeMismatch(expected: "Int", actual: "String")) {
            _ = try kmp.notifier(for: viewModel, result: Int.self)
        }
        // 表示していないインスタンスの判定は、現在の登録の結果型で行われる。
        #expect(throws: KsDialogsKmpError.resultTypeMismatch(expected: "String", actual: "Int")) {
            _ = try kmp.notifier(for: SharedTestDialogViewModel(message: "未表示"), result: String.self)
        }

        notifier.complete("入力")
        #expect(try await showTask.value == .completed("入力"))
    }

    @Test("結果配送後の共有 VM からは報告口を引けない")
    func accessorIsEmptyAfterResultDelivery() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let recorder = KmpModelBindingTestRecorder<Bool>()
        kmp.register(SharedTestDialogViewModel.self) { viewModel in
            recorder.recording(
                KmpModelBindingTestContentView(notifier: try? kmp.notifier(for: viewModel))
            )
        }

        let viewModel = SharedTestDialogViewModel(message: "配送後")
        let showTask = Task { try await kmp.show(viewModel) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))
        try #require(createdView.notifier).complete(true)

        #expect(try await showTask.value == .completed(true))
        #expect(try kmp.notifier(for: viewModel) == nil, "結果が呼び出し元へ渡る時点で紐付けが外れていること")
    }

    @Test("ObjC のクラスとして見える共有 VM でも1引数 factory とアクセサが同じに働く")
    func objectiveCClassViewModelIsSuppliedThroughKmpAccessor() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let recorder = KmpModelBindingTestRecorder<Bool>()
        kmp.register(ObjCSharedTestDialogViewModel.self) { viewModel in
            recorder.recording(
                KmpModelBindingTestContentView(notifier: try? kmp.notifier(for: viewModel))
            )
        }
        let interopRecorder = DialogInteropTestRecorder()

        sharedCodeFace(harness: harness).show(ObjCSharedTestDialogViewModel(message: "確認")) { result in
            interopRecorder.record(result: result)
        }
        let createdView = try await recorder.view(at: 0)

        let notifier = try #require(createdView.notifier, "中身の生成中に報告口が引けること")
        try #require(await harness.waitForPresentedContainers(count: 1))
        notifier.complete(true)

        try #require(await DialogTestWaiting.waitUntil { interopRecorder.resultCount == 1 })
        let result = try #require(interopRecorder.firstResult)
        #expect(result.kind == .completed)
        #expect(result.value as? Bool == true)
    }

    @Test("等価な別インスタンスの共有 VM は互いの報告口を引かない")
    func distinctInstancesDoNotShareNotifier() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let recorder = KmpModelBindingTestRecorder<Bool>()
        kmp.register(SharedTestDialogViewModel.self) { viewModel in
            recorder.recording(
                KmpModelBindingTestContentView(notifier: try? kmp.notifier(for: viewModel))
            )
        }

        let shown = SharedTestDialogViewModel(message: "同じ文言")
        let notShown = SharedTestDialogViewModel(message: "同じ文言")
        let showTask = Task { try await kmp.show(shown) }
        let createdView = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        #expect(try kmp.notifier(for: notShown) == nil, "表示していないインスタンスの報告口は引けないこと")

        try #require(createdView.notifier).complete(true)
        #expect(try await showTask.value == .completed(true))
    }
}
#endif
