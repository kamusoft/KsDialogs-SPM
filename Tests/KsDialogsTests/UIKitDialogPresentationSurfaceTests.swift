#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// UIKit の提示面のうち、テスト実行環境で観察できる範囲 (提示先の解決と提示の依頼) を確かめる。
/// 提示遷移の完了・閉鎖の実挙動はテストランナーでは再現できないため、手動確認で判定する。
@Suite("UIKit の提示先解決", .serialized)
@MainActor
struct UIKitDialogPresentationSurfaceTests {
    private func makeWindow() -> (UIWindow, UIViewController) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let rootViewController = UIViewController()
        window.rootViewController = rootViewController
        window.isHidden = false
        return (window, rootViewController)
    }

    @Test("key window が無ければ提示できない")
    func withoutKeyWindowCannotPresent() {
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: nil)
        )
        #expect(surface.topmostViewController() == nil)
        #expect(surface.canPresent == false)
    }

    @Test("key window の root が提示先になる")
    func rootViewControllerIsPresentationTarget() {
        let (window, rootViewController) = makeWindow()
        defer { window.isHidden = true }
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )

        #expect(surface.canPresent)
        #expect(surface.topmostViewController() === rootViewController)
    }

    @Test("提示の連なりの先端が提示先になる")
    func topmostOfPresentationChainIsPresentationTarget() {
        let (window, rootViewController) = makeWindow()
        defer { window.isHidden = true }
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let presented = UIViewController()
        rootViewController.present(presented, animated: false)

        #expect(surface.topmostViewController() === presented)
    }

    @Test("器は最前面へ提示される")
    func containerIsPresentedFromTopmost() {
        let (window, rootViewController) = makeWindow()
        defer { window.isHidden = true }
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )

        surface.present(container) { _ in }

        #expect(rootViewController.presentedViewController === container)
        #expect(container.modalPresentationStyle == .overFullScreen)
    }

    /// 提示の完了通知を届いた順に書き留める。
    @MainActor
    private final class PresentationObservation {
        private(set) var results: [Bool] = []

        func record(_ didPresent: Bool) {
            results.append(didPresent)
        }
    }

    @Test("受け付けられた提示は、この呼び出しの中で載せられなかったとは知らせない")
    func acceptedPresentationIsNotReportedAsFailure() {
        let (window, rootViewController) = makeWindow()
        defer { window.isHidden = true }
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )
        let observation = PresentationObservation()

        surface.present(container) { observation.record($0) }

        #expect(rootViewController.presentedViewController === container, "提示関係は呼び出しの中で結ばれる")
        #expect(!observation.results.contains(false), "載せられなかったとは知らせない")
    }

    @Test("提示機構が提示を受け付けないと、載せられなかったとちょうど 1 回知らせる")
    func refusedPresentationIsReportedOnce() {
        let (window, rootViewController) = makeWindow()
        defer { window.isHidden = true }
        // 提示元の View が画面の階層に無いと、提示機構は提示を受け付けず完了通知も届けない。
        rootViewController.view.removeFromSuperview()
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )
        let observation = PresentationObservation()

        surface.present(container) { observation.record($0) }

        #expect(container.presentingViewController == nil, "提示機構は提示を受け付けていない")
        #expect(rootViewController.transitionCoordinator == nil, "持ち越す遷移は無い")
        #expect(observation.results == [false], "載せられなかったことが呼び出しの中でちょうど 1 回届く")
    }

    @Test("提示元の遷移の最中の提示は持ち越されるので、その場では載せられなかったと知らせない")
    func presentationDeferredByTransitionIsNotReportedImmediately() throws {
        let (window, rootViewController) = makeWindow()
        defer { window.isHidden = true }
        // 閉じる途中の画面を提示中の提示元。提示遷移はテスト実行環境では完走しないので、遷移の最中が続く。
        rootViewController.present(BeingDismissedViewController(), animated: false)
        try #require(rootViewController.transitionCoordinator != nil, "提示元は遷移の最中にある")
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )
        let observation = PresentationObservation()

        #expect(surface.topmostViewController() === rootViewController, "閉じる途中の画面の手前が提示先に選ばれる")
        surface.present(container) { observation.record($0) }

        #expect(container.presentingViewController == nil, "提示は遷移の終わりまで持ち越されている")
        #expect(observation.results.isEmpty, "結べるかは遷移の終わりに決まるので、まだ知らせない")
    }

    @Test("遷移の完了を見張れず提示関係も結ばれていなければ、その場で載せられなかったとちょうど 1 回知らせる")
    func unobservableTransitionWithoutBindingIsReportedOnce() throws {
        let (window, rootViewController) = makeWindow()
        defer { window.isHidden = true }
        // 閉じる途中の画面を提示中の提示元。提示は遷移の終わりまで持ち越され、呼び出しの中では結ばれない。
        rootViewController.present(BeingDismissedViewController(), animated: false)
        try #require(rootViewController.transitionCoordinator != nil, "提示元は遷移の最中にある")
        // 遷移の完了の見張りを登録できない提示機構 (登録を差し替えて再現する)。
        let registrations = DialogTestCallCounter()
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window),
            observeTransitionCompletion: { _, _ in
                registrations.increment()
                return false
            }
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )
        let observation = PresentationObservation()

        surface.present(container) { observation.record($0) }

        #expect(registrations.count == 1, "遷移の完了の見張りの登録を試みている")
        #expect(container.presentingViewController == nil, "提示関係は結ばれていない")
        #expect(observation.results == [false], "見張れないので、その場でちょうど 1 回知らせる")
    }

    @Test("載せられなかったと知らせた後に提示が遅れて結ばれると、器を画面から外し、知らせは変えない")
    func lateBoundPresentationAfterFailureIsDismissed() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let presenting = LateBindingPresentingViewController()
        window.rootViewController = presenting
        window.isHidden = false
        defer { window.isHidden = true }
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )
        let observation = PresentationObservation()

        surface.present(container) { observation.record($0) }
        #expect(observation.results == [false], "提示関係も遷移も無いので、載せられなかったと知らせる")

        // 提示機構が遅れて提示を結び、完了通知を流す。
        presenting.bindHeldPresentation()

        // 閉鎖の遷移はテストランナーでは完走しないため、提示元へ閉鎖が依頼されたことで見る。
        #expect(presenting.dismissalRequests == [false], "遅れて結ばれた器を、アニメーションなしで閉じる")
        #expect(observation.results == [false], "知らせは載せられなかったのまま変わらない")
    }

    @Test("提示先が無いと、載せられなかったとちょうど 1 回知らせる")
    func missingHostIsReportedOnce() {
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: nil)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )
        let observation = PresentationObservation()

        surface.present(container) { observation.record($0) }

        #expect(observation.results == [false])
    }

    /// 閉鎖の完了通知が届いたかどうかを書き留める。
    @MainActor
    private final class DismissalObservation {
        private(set) var didComplete = false

        func record() {
            didComplete = true
        }
    }

    /// 提示の連なりに載っていない器を閉じても完了は届く。
    ///
    /// 提示機構へ渡す前に打ち切る経路であり、テストランナーでも観察できる。
    /// 提示済みの器を閉じたときの完了は提示遷移の完走を伴うため、この環境では届かない
    /// (シーンを持たないテストランナーでは提示遷移そのものが完走しない)。
    @Test("提示されていない器の閉鎖でも完了は届く")
    func dismissCompletionArrivesForUnpresentedContainer() async {
        let (window, _) = makeWindow()
        defer { window.isHidden = true }
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )

        let observation = DismissalObservation()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            surface.dismiss(container) {
                observation.record()
                continuation.resume()
            }
        }

        #expect(observation.didComplete, "待つ相手がいなくても完了は届く")
    }

    @Test("提示元の閉鎖の完了がそのまま撤去の完了になる")
    func dismissCompletionArrivesFromPresentingViewController() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let presenting = RecordingPresentingViewController()
        window.rootViewController = presenting
        window.isHidden = false
        defer { window.isHidden = true }
        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )
        surface.present(container) { _ in }
        try #require(container.presentingViewController === presenting)

        let observation = DismissalObservation()
        surface.dismiss(container) { observation.record() }

        #expect(
            presenting.dismissalRequests == [false],
            "提示元へアニメーションなしの閉鎖がちょうど1回依頼される"
        )
        #expect(observation.didComplete, "提示元の完了通知が撤去の完了として流れる")
    }
}
#endif
