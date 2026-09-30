#if canImport(UIKit)
import UIKit

/// key window の root から present の連なりを辿り、その先端からダイアログを提示する面。
final class UIKitDialogPresentationSurface: DialogPresentationSurface {
    /// 提示元の遷移の完了を見張る登録。遷移の完了で `handler` を呼ぶよう登録できたら true を返す。
    typealias TransitionCompletionObservation = @MainActor (
        _ coordinator: any UIViewControllerTransitionCoordinator,
        _ handler: @escaping @MainActor () -> Void
    ) -> Bool

    private let keyWindowProvider: any DialogKeyWindowProvider
    private let observeTransitionCompletion: TransitionCompletionObservation
    let hostWaitQueue: DialogHostWaitQueue

    /// - Parameters:
    ///   - keyWindowProvider: 提示先の window の供給元
    ///   - hostWaitQueue: 提示先を待つ show の列。既定はアプリケーションの提示先を共有する全 show の列
    ///   - observeTransitionCompletion: 提示元の遷移の完了を見張る登録。既定は提示機構の遷移の完了通知に載せる
    init(
        keyWindowProvider: any DialogKeyWindowProvider = ApplicationKeyWindowProvider(),
        hostWaitQueue: DialogHostWaitQueue = .application,
        observeTransitionCompletion: @escaping TransitionCompletionObservation = UIKitDialogPresentationSurface
            .observeCompletionOfTransition
    ) {
        self.keyWindowProvider = keyWindowProvider
        self.hostWaitQueue = hostWaitQueue
        self.observeTransitionCompletion = observeTransitionCompletion
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
    func present(
        _ container: DialogContainerViewController,
        completion: @escaping DialogPresentationCompletion
    ) {
        guard let topmost = topmostViewController() else {
            // 提示先を確かめてから中身を作るまでの間 (利用者の factory の中など) に提示先が消えた。
            completion(false)
            return
        }
        let latch = DialogPresentationCompletionLatch(completion)
        // 出入りの演出は器が自前で駆動するため、提示機構のトランジションは使わない (core/ADR-0017)。
        topmost.present(container, animated: false) {
            // 提示機構の完了通知はメインスレッドで届く。
            MainActor.assumeIsolated {
                if latch.hasReportedFailure {
                    // 載せられなかったと知らせた後に、提示機構が遅れて提示を結んだ。
                    // 器は cancelled で確定して片付け済みなので、結果は変えずに画面からだけ外す。
                    container.presentingViewController?.dismiss(animated: false)
                    return
                }
                latch.report(true)
            }
        }
        // 受け付けられた提示は、この呼び出しの中で提示関係が結ばれる。
        guard container.presentingViewController == nil else { return }
        guard let coordinator = topmost.transitionCoordinator else {
            // 提示元が別の画面を提示中などで、提示機構が提示を拒否した。完了通知は届かない。
            latch.report(false)
            return
        }
        // 提示元の遷移 (閉じる途中の画面の閉鎖など) の最中は、提示機構は提示を遷移の終わりまで持ち越す。
        // 持ち越した提示は遷移の完了通知までに結ばれ、そのとき結べなかった提示は拒否されて完了通知も届かない。
        let isObserving = observeTransitionCompletion(coordinator) {
            if container.presentingViewController == nil {
                latch.report(false)
            }
        }
        // 遷移の完了を見張れないと、拒否された提示の知らせがどこからも届かない。その場で提示関係を確かめ直し、
        // 結ばれていなければ載せられなかったとする (後から結ばれたら、上の完了通知で器を画面から外す)。
        if !isObserving, container.presentingViewController == nil {
            latch.report(false)
        }
    }

    /// 提示機構の遷移の完了通知に `handler` を載せる。載せられなければ false。
    @MainActor
    static func observeCompletionOfTransition(
        _ coordinator: any UIViewControllerTransitionCoordinator,
        handler: @escaping @MainActor () -> Void
    ) -> Bool {
        coordinator.animate(alongsideTransition: nil) { _ in
            handler()
        }
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

    @MainActor
    func observeHostAppearance(
        _ handler: @escaping DialogHostAppearanceHandler
    ) -> DialogHostAppearanceRegistration {
        keyWindowProvider.observeHostAppearance(handler)
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
