#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 提示先を確かめて中身を作ったあとに、提示面が器を載せられなかった show の結末を確かめる。
///
/// 載せられなかった show は、器の消失と同じく cancelled で終わり、提示先を待つ列の番を返す。
/// 載せられない場面は、提示先が中身の生成中に消える場合と、提示機構が提示を受け付けない場合の 2 つ。
/// 提示機構が遷移の完了の見張りを受け付けない場合は、提示面の見張りの登録を差し替えて再現する。
/// 載せられなかったと判定した後に提示が遅れて結ばれる場合は、提示を預かって後から結ぶ提示元で再現する。
/// 提示元の遷移の最中に持ち越された提示が遷移の終わりに拒否される場合は、提示遷移が完走する
/// ホストアプリの上でしか再現できないため、MAUI の iOS 互換面のテストで確かめる。
@Suite("器を載せられなかった Dialog", .serialized)
@MainActor
struct DialogPresentationRefusalTests {
    /// show の戻り値を書き留める。戻らない show を時間切れで見分けるために使う。
    @MainActor
    private final class ShowResults {
        private(set) var results: [String: DialogResult<Bool>] = [:]

        func record(_ result: DialogResult<Bool>, for name: String) {
            results[name] = result
        }
    }

    private static func makeWindow(root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root
        window.isHidden = false
        return window
    }

    private static func isCancelled(_ result: DialogResult<Bool>?) -> Bool {
        if case .cancelled = result { return true }
        return false
    }

    @Test("提示機構が提示を受け付けないと、列から明けた show は cancelled で終わり、後ろの show も明ける")
    func refusedPresentationEndsAsCancelledAndReleasesQueue() async throws {
        // 提示元の View が画面の階層に無く、提示機構は提示を受け付けない (完了通知も届かない)。
        let root = UIViewController()
        let window = Self.makeWindow(root: root)
        defer { window.isHidden = true }
        root.view.removeFromSuperview()
        let provider = DialogTestKeyWindowProvider(keyWindow: nil)
        let surface = UIKitDialogPresentationSurface(keyWindowProvider: provider, hostWaitQueue: DialogHostWaitQueue())
        let registry = DialogViewRegistry()
        let supplied = DialogTestCallCounter()
        registry.register(BasicTestDialogViewModel.self) { _, _ in
            supplied.increment()
            return DialogTestContentView()
        }
        let dialog = Dialog(registry: registry, presentationSurface: surface)
        let results = ShowResults()
        let viewModelA = BasicTestDialogViewModel(message: "A")
        let viewModelB = BasicTestDialogViewModel(message: "B")

        // 提示先が無い間に A、B の順で呼び、列に並べる。
        Task { results.record(try await dialog.show(viewModelA), for: "A") }
        Task { results.record(try await dialog.show(viewModelB), for: "B") }
        try #require(await DialogTestWaiting.waitUntil { surface.hostWaitQueue.waitingCount == 2 })

        provider.keyWindow = window
        provider.fireHostAppearance()

        #expect(
            await DialogTestWaiting.waitUntil { results.results.count == 2 },
            "A も B も戻る (A の番が返らないと B は列に残り、A も戻らない)"
        )
        #expect(Self.isCancelled(results.results["A"]), "載せられなかった A は cancelled で終わる")
        #expect(Self.isCancelled(results.results["B"]), "A の後に明けた B も、同じ理由で cancelled で終わる")
        #expect(supplied.count == 2, "A も B も列から明けて中身が作られている")
        #expect(surface.hostWaitQueue.waitingCount == 0, "列に残っていない")
        #expect(viewModelA.notifier == nil, "A の報告口の紐付けは解除されている")
        #expect(viewModelB.notifier == nil, "B の報告口の紐付けは解除されている")
        #expect(root.presentedViewController == nil, "器は提示の連なりに載っていない")
    }

    @Test("遷移の完了を見張れず提示も結ばれないと、列から明けた show は cancelled で終わり、後ろの show も明ける")
    func unobservableTransitionEndsAsCancelledAndReleasesQueue() async throws {
        // 閉じる途中の画面を提示中の提示元。提示は遷移の終わりまで持ち越され、呼び出しの中では結ばれない。
        let root = UIViewController()
        let window = Self.makeWindow(root: root)
        defer { window.isHidden = true }
        root.present(BeingDismissedViewController(), animated: false)
        try #require(root.transitionCoordinator != nil, "提示元は遷移の最中にある")
        let provider = DialogTestKeyWindowProvider(keyWindow: nil)
        // 遷移の完了の見張りを登録できない提示機構 (登録を差し替えて再現する)。
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: provider,
            hostWaitQueue: DialogHostWaitQueue(),
            observeTransitionCompletion: { _, _ in false }
        )
        let registry = DialogViewRegistry()
        let supplied = DialogTestCallCounter()
        registry.register(BasicTestDialogViewModel.self) { _, _ in
            supplied.increment()
            return DialogTestContentView()
        }
        let dialog = Dialog(registry: registry, presentationSurface: surface)
        let results = ShowResults()
        let viewModelA = BasicTestDialogViewModel(message: "A")
        let viewModelB = BasicTestDialogViewModel(message: "B")

        Task { results.record(try await dialog.show(viewModelA), for: "A") }
        Task { results.record(try await dialog.show(viewModelB), for: "B") }
        try #require(await DialogTestWaiting.waitUntil { surface.hostWaitQueue.waitingCount == 2 })

        provider.keyWindow = window
        provider.fireHostAppearance()

        #expect(
            await DialogTestWaiting.waitUntil { results.results.count == 2 },
            "A も B も戻る (A の番が返らないと B は列に残り、A も戻らない)"
        )
        #expect(Self.isCancelled(results.results["A"]), "載せられなかった A は cancelled で終わる")
        #expect(Self.isCancelled(results.results["B"]), "A の後に明けた B も、同じ理由で cancelled で終わる")
        #expect(supplied.count == 2, "A も B も列から明けて中身が作られている")
        #expect(surface.hostWaitQueue.waitingCount == 0, "列に残っていない")
        #expect(viewModelA.notifier == nil, "A の報告口の紐付けは解除されている")
        #expect(viewModelB.notifier == nil, "B の報告口の紐付けは解除されている")
    }

    @Test("cancelled で終わった後に提示が遅れて結ばれても、器は画面に残らず、結果も変わらない")
    func lateBoundPresentationAfterCancellationIsRemoved() async throws {
        let root = LateBindingPresentingViewController()
        let window = Self.makeWindow(root: root)
        defer { window.isHidden = true }
        let provider = DialogTestKeyWindowProvider(keyWindow: window)
        let surface = UIKitDialogPresentationSurface(keyWindowProvider: provider, hostWaitQueue: DialogHostWaitQueue())
        let registry = DialogViewRegistry()
        registry.register(BasicTestDialogViewModel.self) { _, _ in DialogTestContentView() }
        let dialog = Dialog(registry: registry, presentationSurface: surface)
        let results = ShowResults()
        let viewModel = BasicTestDialogViewModel(message: "A")

        Task { results.record(try await dialog.show(viewModel), for: "A") }

        #expect(await DialogTestWaiting.waitUntil { results.results["A"] != nil }, "A は戻る")
        #expect(Self.isCancelled(results.results["A"]), "載せられなかった A は cancelled で終わる")

        // 提示機構が遅れて提示を結び、完了通知を流す。
        root.bindHeldPresentation()

        // シーンを持たないテストランナーでは閉鎖の遷移が完走しないため、画面から外れるところまでは
        // 見られない。提示元へ閉鎖が依頼されたことで見る (実際に外れることは MAUI の iOS 互換面のテストで見る)。
        #expect(root.dismissalRequests == [false], "遅れて結ばれた片付け済みの器を、アニメーションなしで閉じる")
        #expect(Self.isCancelled(results.results["A"]), "確定済みの結果は変わらない")
        #expect(viewModel.notifier == nil, "報告口の紐付けは解除されたまま")
    }

    @Test("提示先が中身の生成中に消えると、show は cancelled で終わり、後ろの show は提示先の出現を待つ")
    func hostVanishingDuringContentCreationEndsAsCancelled() async throws {
        let root = RecordingPresentingViewController()
        let window = Self.makeWindow(root: root)
        defer { window.isHidden = true }
        let provider = DialogTestKeyWindowProvider(keyWindow: nil)
        let surface = UIKitDialogPresentationSurface(keyWindowProvider: provider, hostWaitQueue: DialogHostWaitQueue())
        let registry = DialogViewRegistry()
        let supplied = DialogTestCallCounter()
        registry.register(BasicTestDialogViewModel.self) { viewModel, _ in
            supplied.increment()
            if viewModel.message == "A" {
                // 利用者の factory の中で提示先が失われる (window の破棄など)。
                provider.keyWindow = nil
            }
            return DialogTestContentView()
        }
        let dialog = Dialog(registry: registry, presentationSurface: surface)
        let results = ShowResults()
        let viewModelA = BasicTestDialogViewModel(message: "A")
        let viewModelB = BasicTestDialogViewModel(message: "B")

        Task { results.record(try await dialog.show(viewModelA), for: "A") }
        Task { results.record(try await dialog.show(viewModelB), for: "B") }
        try #require(await DialogTestWaiting.waitUntil { surface.hostWaitQueue.waitingCount == 2 })

        provider.keyWindow = window
        provider.fireHostAppearance()

        #expect(await DialogTestWaiting.waitUntil { results.results["A"] != nil }, "A は戻る")
        #expect(Self.isCancelled(results.results["A"]), "載せられなかった A は cancelled で終わる")
        #expect(viewModelA.notifier == nil, "A の報告口の紐付けは解除されている")
        #expect(root.presentedViewController == nil, "A の器は提示されていない")
        #expect(surface.hostWaitQueue.waitingCount == 1, "B は提示先が無いので列で待ち続ける")

        // 提示先が戻れば、A の番に塞がれずに B が明ける。
        provider.keyWindow = window
        provider.fireHostAppearance()

        #expect(
            await DialogTestWaiting.waitUntil { root.presentedViewController is DialogContainerViewController },
            "B が表示される"
        )
        #expect(supplied.count == 2)

        // 後始末: B の結果を報告し、器を window に載せて撤去まで進める
        // (シーンを持たないテストランナーでは提示遷移が完走せず、器が window に載らない)。
        let container = try #require(root.presentedViewController as? DialogContainerViewController)
        container.view.frame = window.bounds
        window.addSubview(container.view)
        try #require(viewModelB.notifier).complete(true)
        #expect(await DialogTestWaiting.waitUntil { results.results["B"] != nil }, "B は報告した結果で戻る")
        if case .completed(let value) = results.results["B"] {
            #expect(value)
        } else {
            Issue.record("B は completed(true) で戻る")
        }
    }
}
#endif
