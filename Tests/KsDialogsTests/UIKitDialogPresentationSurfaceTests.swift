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

        surface.present(container)

        #expect(rootViewController.presentedViewController === container)
        #expect(container.modalPresentationStyle == .overFullScreen)
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
        surface.present(container)
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
