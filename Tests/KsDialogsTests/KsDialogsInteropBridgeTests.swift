#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("KMP 委譲向け互換面の提供", .serialized)
@MainActor
struct KsDialogsInteropBridgeTests {
    @Test("ObjC 互換面経由の呼び出しが同一レジストリに到達する")
    func interopRegistrationIsResolvedFromBothEntryPoints() async throws {
        let harness = DialogTestHarness()
        let bridge = KsDialogsInteropBridge(
            registry: harness.registry,
            presentationSurface: harness.presentationSurface
        )
        let recorder = DialogInteropTestRecorder()
        bridge.registerViewFactory(
            forViewModelClass: InteropTestDialogViewModel.self,
            resultType: KsDialogsInteropResultType(name: "Bool") { $0 is Bool }
        ) { _, notifier in
            recorder.record(notifier: notifier)
            return DialogTestContentView()
        }

        bridge.show(InteropTestDialogViewModel(message: "こんにちは")) { result in
            recorder.record(result: result)
        }
        try #require(await DialogTestWaiting.waitUntil { recorder.notifierCount == 1 })
        #expect(harness.presentedContainers.count == 1)
        recorder.notifier(at: 0)?.complete(true)

        try #require(await DialogTestWaiting.waitUntil { recorder.resultCount == 1 })
        let result = try #require(recorder.firstResult)
        #expect(result.kind == .completed)
        #expect(result.value as? Bool == true)
        #expect(result.error == nil)

        // 同じレジストリであることを、型付きの入口から同じキーで解決できることでも確かめる。
        try #require(await harness.waitForPresentedContainers(count: 0))
        let showTask = Task { try await harness.dialogs.show(InteropTestDialogViewModel(message: "こんにちは")) }
        try #require(await DialogTestWaiting.waitUntil { recorder.notifierCount == 2 })
        recorder.notifier(at: 1)?.complete(false)
        #expect(try await showTask.value == .completed(false))
    }

    @Test("互換面経由でも結果は1回だけ届く")
    func interopCompletionIsDeliveredOnce() async throws {
        let harness = DialogTestHarness()
        let bridge = KsDialogsInteropBridge(
            registry: harness.registry,
            presentationSurface: harness.presentationSurface
        )
        let recorder = DialogInteropTestRecorder()
        bridge.registerViewFactory(
            forViewModelClass: InteropTestDialogViewModel.self,
            resultType: KsDialogsInteropResultType(name: "Bool") { $0 is Bool }
        ) { _, notifier in
            recorder.record(notifier: notifier)
            return DialogTestContentView()
        }

        bridge.show(InteropTestDialogViewModel(message: "こんにちは")) { result in
            recorder.record(result: result)
        }
        try #require(await DialogTestWaiting.waitUntil { recorder.notifierCount == 1 })
        let notifier = try #require(recorder.notifier(at: 0))
        notifier.complete(true)
        try #require(await DialogTestWaiting.waitUntil { recorder.resultCount == 1 })

        notifier.complete(false)
        notifier.cancel()
        _ = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) { recorder.resultCount > 1 }

        #expect(recorder.resultCount == 1)
        #expect(recorder.firstResult?.value as? Bool == true)
    }

    @Test("宣言結果型と合わない結果値の報告は失敗として返る")
    func interopMismatchedResultValueReportsError() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogInteropTestRecorder()
        let bridge = registeredBridge(harness: harness, recorder: recorder)

        bridge.show(InteropTestDialogViewModel(message: "こんにちは")) { result in
            recorder.record(result: result)
        }
        try #require(await DialogTestWaiting.waitUntil { recorder.notifierCount == 1 })
        recorder.notifier(at: 0)?.complete("文字列")

        try #require(await DialogTestWaiting.waitUntil { recorder.resultCount == 1 })
        let result = try #require(recorder.firstResult)
        #expect(result.kind == .error)
        #expect(result.value == nil)
        #expect(result.error as? DialogError == .resultTypeMismatch(expected: "Bool", actual: "String"))
        // 不一致でも自分のダイアログは閉じ、cancelled には化けない。
        #expect(await harness.waitForPresentedContainers(count: 0))
    }

    @Test("nil を包んだ結果値の報告も失敗として返る")
    func interopNilResultValueReportsError() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogInteropTestRecorder()
        let bridge = registeredBridge(harness: harness, recorder: recorder)

        bridge.show(InteropTestDialogViewModel(message: "こんにちは")) { result in
            recorder.record(result: result)
        }
        try #require(await DialogTestWaiting.waitUntil { recorder.notifierCount == 1 })
        let missingValue: Bool? = nil
        recorder.notifier(at: 0)?.complete(missingValue as Any)

        try #require(await DialogTestWaiting.waitUntil { recorder.resultCount == 1 })
        let result = try #require(recorder.firstResult)
        #expect(result.kind == .error)
        #expect(result.value == nil)
        #expect(result.error as? DialogError == .resultTypeMismatch(expected: "Bool", actual: "Optional<Bool>"))
    }

    @Test("型が合わない報告で確定した後の再報告は無効")
    func interopMismatchKeepsExactlyOnceGuarantee() async throws {
        let harness = DialogTestHarness()
        let recorder = DialogInteropTestRecorder()
        let bridge = registeredBridge(harness: harness, recorder: recorder)

        bridge.show(InteropTestDialogViewModel(message: "こんにちは")) { result in
            recorder.record(result: result)
        }
        try #require(await DialogTestWaiting.waitUntil { recorder.notifierCount == 1 })
        let notifier = try #require(recorder.notifier(at: 0))
        notifier.complete("文字列")
        try #require(await DialogTestWaiting.waitUntil { recorder.resultCount == 1 })

        notifier.complete(true)
        notifier.cancel()
        _ = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) { recorder.resultCount > 1 }

        #expect(recorder.resultCount == 1)
        #expect(recorder.firstResult?.kind == .error)
    }

    /// 結果型 Bool を宣言した ViewModel の View factory を登録した互換面を用意する。
    private func registeredBridge(
        harness: DialogTestHarness,
        recorder: DialogInteropTestRecorder
    ) -> KsDialogsInteropBridge {
        let bridge = KsDialogsInteropBridge(
            registry: harness.registry,
            presentationSurface: harness.presentationSurface
        )
        bridge.registerViewFactory(
            forViewModelClass: InteropTestDialogViewModel.self,
            resultType: KsDialogsInteropResultType(name: "Bool") { $0 is Bool }
        ) { _, notifier in
            recorder.record(notifier: notifier)
            return DialogTestContentView()
        }
        return bridge
    }

    @Test("互換面へ渡した placement が配置に効く")
    func interopPlacementIsAppliedToLayout() async throws {
        let harness = DialogTestHarness()
        let bridge = KsDialogsInteropBridge(
            registry: harness.registry,
            presentationSurface: harness.presentationSurface
        )
        let recorder = DialogInteropTestRecorder()
        bridge.registerViewFactory(
            forViewModelClass: InteropTestDialogViewModel.self,
            resultType: KsDialogsInteropResultType(name: "Bool") { $0 is Bool }
        ) { _, notifier in
            recorder.record(notifier: notifier)
            let contentView = FixedContentSizeView(contentSize: CGSize(width: 280, height: 180))
            // 期待値の導出を単純にするため、基準領域はウィンドウ全体・余白なしにする。
            contentView.ksDialogOptions = DialogOptions(layoutArea: .window, dialogMargin: .zero)
            return contentView
        }

        bridge.show(
            InteropTestDialogViewModel(message: "こんにちは"),
            placement: KsDialogsInteropPlacement(
                horizontalAlignment: .start,
                verticalAlignment: .end,
                offsetX: 10,
                offsetY: 0
            )
        ) { result in
            recorder.record(result: result)
        }
        try #require(await DialogTestWaiting.waitUntil { recorder.notifierCount == 1 })
        let frame = try #require(harness.presentationSurface.contentFramesAtPresentation.first)
        recorder.notifier(at: 0)?.complete(true)
        try #require(await DialogTestWaiting.waitUntil { recorder.resultCount == 1 })

        // 提示面の 390 × 844 に対し、水平は Start + Offset 10、垂直は End。
        DialogRectExpectation.expect(frame, equals: CGRect(x: 10, y: 664, width: 280, height: 180))
    }

    @Test("未登録の ViewModel は互換面では error 判別で返る")
    func interopUnregisteredViewModelReportsError() async throws {
        let harness = DialogTestHarness()
        let bridge = KsDialogsInteropBridge(
            registry: harness.registry,
            presentationSurface: harness.presentationSurface
        )
        let recorder = DialogInteropTestRecorder()

        bridge.show(InteropTestDialogViewModel(message: "こんにちは")) { result in
            recorder.record(result: result)
        }

        try #require(await DialogTestWaiting.waitUntil { recorder.resultCount == 1 })
        let result = try #require(recorder.firstResult)
        #expect(result.kind == .error)
        #expect(result.value == nil)
        #expect(result.error != nil)
        #expect(harness.presentedContainers.isEmpty)
    }
}
#endif
