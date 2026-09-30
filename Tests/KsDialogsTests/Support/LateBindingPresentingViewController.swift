#if canImport(UIKit)
import UIKit

/// 提示の依頼をその場では結ばず、後から結べる提示元。
///
/// 提示機構が提示を受け付けなかったように見せたあと (提示関係も遷移も無い)、`bindHeldPresentation()` で
/// 提示関係を結んで完了通知を流す。「載せられなかった」と判定した後に提示が遅れて結ばれる場面は、
/// 実物の提示機構ではテスト実行環境で作れないため、これで再現する。
@MainActor
final class LateBindingPresentingViewController: UIViewController {
    private var heldViewController: UIViewController?
    private var heldCompletion: (() -> Void)?

    /// 受け取った閉鎖依頼のアニメーション指定 (受け取った順)。
    private(set) var dismissalRequests: [Bool] = []

    /// 提示の依頼を預かるだけで、提示関係は結ばない。
    override func present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)? = nil
    ) {
        heldViewController = viewControllerToPresent
        heldCompletion = completion
    }

    /// 預かった提示を結び、提示機構の完了通知を流す。
    func bindHeldPresentation() {
        guard let viewController = heldViewController else { return }
        let completion = heldCompletion
        heldViewController = nil
        heldCompletion = nil
        super.present(viewController, animated: false, completion: nil)
        completion?()
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissalRequests.append(flag)
        super.dismiss(animated: flag, completion: completion)
    }
}
#endif
