#if canImport(UIKit)
import UIKit

/// key window の root から present の連なりを辿り、その先端からダイアログを提示する面。
final class UIKitDialogPresentationSurface: DialogPresentationSurface {
    private let keyWindowProvider: any DialogKeyWindowProvider

    init(keyWindowProvider: any DialogKeyWindowProvider = ApplicationKeyWindowProvider()) {
        self.keyWindowProvider = keyWindowProvider
    }

    @MainActor
    var canPresent: Bool {
        topmostViewController() != nil
    }

    @MainActor
    var presentationBounds: CGRect {
        guard let topmost = topmostViewController() else { return .zero }
        return topmost.view.window?.bounds ?? topmost.view.bounds
    }

    @MainActor
    func present(_ container: DialogContainerViewController) {
        // 出入りの演出は器が自前で駆動するため、提示機構のトランジションは使わない (core/ADR-0017)。
        topmostViewController()?.present(container, animated: false)
    }

    @MainActor
    func dismiss(
        _ container: DialogContainerViewController,
        completion: @escaping DialogRemovalCompletion
    ) {
        // 提示元から閉じることで、自分より手前のダイアログの閉鎖と取り違えない。
        guard let presenting = container.presentingViewController else {
            // 既に提示の連なりから外れている。撤去は済んでいるのでその場で知らせる。
            completion()
            return
        }
        presenting.dismiss(animated: false) {
            // 提示機構の完了通知はメインスレッドで届く。
            MainActor.assumeIsolated {
                completion()
            }
        }
    }

    /// present の連なりの先端。提示できる画面がなければ nil。
    @MainActor
    func topmostViewController() -> UIViewController? {
        guard var topmost = keyWindowProvider.keyWindow?.rootViewController else { return nil }
        while let presented = topmost.presentedViewController {
            // 閉じる途中の ViewController は次の提示先にできないため、そこで打ち切る。
            if presented.isBeingDismissed { break }
            topmost = presented
        }
        return topmost
    }
}
#endif
