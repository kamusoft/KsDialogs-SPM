#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 開始が成立しなかったときに、合流状態も器も残らないことを確かめる。
///
/// 中身を作る factory は利用者のコードであり、型が食い違えば中身を作れずに失敗する。
/// 失敗した開始が「開始した」状態を残すと、以後の Loading が表示の成立しない世代へ合流してしまう。
/// 呼び出し元が取り消された場合も同じく、握った合流1件を終了まで数え切る必要がある。
@Suite("成立しなかった Loading の開始", .serialized)
@MainActor
struct LoadingStartFailureTests {
    private static let contentSize = CGSize(width: 120, height: 80)

    @Test("中身の生成に失敗した開始は合流も器も残さない")
    func failedContentCreationLeavesNoState() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let actionRecorder = LoadingTestActionRecorder()
        // ViewModel の型が factory の想定と食い違う登録を作り、中身の生成を失敗させる。
        harness.registry.register(
            LoadingViewFactory.make(ProgressReceivingLoadingTestViewModel.self) { _ in
                FixedContentSizeView(contentSize: Self.contentSize)
            },
            forKey: DialogViewModelKey(LoadingTestViewModel.self)
        )

        await #expect(throws: DialogError.viewFactoryTypeMismatch(
            viewModelType: String(describing: LoadingTestViewModel.self))) {
            try await harness.loading.start(LoadingTestViewModel()) { _ in
                await MainActor.run { actionRecorder.recordCompletion() }
            }
        }

        #expect(actionRecorder.completionCount == 0, "action は実行されない")
        #expect(harness.coordinator.coalescedUseCount == 0, "合流は残らない")
        #expect(harness.isPresenting == false, "表示は成立しない")
        #expect(harness.contentView == nil, "中身も残らない")

        // 後続の開始は失敗した世代へ合流せず、新しい表示として成立する。
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            viewRecorder.record(view)
            return view
        }

        try await harness.loading.show(LoadingTestViewModel())

        #expect(harness.isPresenting, "後続の表示は成立する")
        #expect(harness.coordinator.coalescedUseCount == 1)
        #expect(harness.contentView === viewRecorder.lastView)

        await harness.loading.hide()
    }

    @Test("factory が投げた失敗は開始の失敗になり、合流も器も残らない")
    func throwingFactoryFailsTheStart() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        // 中身の作り手が失敗を投げる登録。互換面 (MAUI / KMP) の中身の供給元が
        // 中身を作れなかった場合もこの経路を通る。
        harness.registry.register(LoadingTestViewModel.self) { _ throws -> UIView in
            throw LoadingStartTestContentFailure.cannotMakeContent
        }

        await #expect(throws: LoadingStartTestContentFailure.cannotMakeContent) {
            try await harness.loading.show(LoadingTestViewModel())
        }

        #expect(harness.coordinator.coalescedUseCount == 0, "合流は残らない")
        #expect(harness.isPresenting == false, "表示は成立しない")
        #expect(harness.contentView == nil, "中身も残らない")
    }

    @Test("受理直後に取り消された開始でも合流は数え切られる")
    func cancellationRightAfterAcceptanceStillEndsUse() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let callerBox = CallerTaskBox()
        // 取り付け先を読むのは合流の受理が済んだ後の器の組み立てなので、
        // 「状態は確定したが呼び出し元へ身分証が渡っていない」時点をここで捕まえられる。
        let surface = HostReadHookSurface(host: harness.window) { callerBox.cancelCaller() }
        let coordinator = LoadingCoordinator(
            registry: LoadingViewRegistry(),
            settings: LoadingSettings(),
            presentationSurface: surface
        )
        let loading = Loading(coordinator: coordinator)
        let actionRecorder = LoadingTestActionRecorder()
        let startGate = DialogTransitionGate()

        let caller = Task { @MainActor in
            // 取り消しの相手を登録し終えてから開始させる。
            try await startGate.wait()
            try await loading.start(message: "待機中") { _ in
                await MainActor.run { actionRecorder.recordCompletion() }
            }
        }
        callerBox.caller = caller
        startGate.open()
        _ = try await caller.value

        #expect(caller.isCancelled, "呼び出し元は取り消されている")
        // Swift の取り消しは協調的で、受理の後に身分証が失われることはない。
        // そのため処理はそのまま走り、終了も1回だけ数えられる。
        #expect(actionRecorder.completionCount == 1, "身分証は失われず処理が走る")
        #expect(coordinator.coalescedUseCount == 0, "合流は残らない")
        #expect(coordinator.isPresenting == false, "器は撤去済み")
        #expect(coordinator.presentedContainer == nil)
    }

    /// 取り消しの相手にする呼び出し元を、面のフックから触れるように取り置く。
    @MainActor
    private final class CallerTaskBox {
        var caller: Task<Void, any Error>?

        func cancelCaller() {
            caller?.cancel()
        }
    }

    /// 取り付け先を読んだ瞬間に指定の処理を差し込む面。
    @MainActor
    private final class HostReadHookSurface: LoadingPresentationSurface {
        private let host: UIView
        private let onHostRead: @MainActor () -> Void

        init(host: UIView, onHostRead: @escaping @MainActor () -> Void) {
            self.host = host
            self.onHostRead = onHostRead
        }

        var hostView: UIView? {
            onHostRead()
            return host
        }
    }
}

/// 中身の作り手が投げる失敗。factory の例外が開始の失敗として返ることの再現に使う。
enum LoadingStartTestContentFailure: Error, Equatable {
    case cannotMakeContent
}
#endif
