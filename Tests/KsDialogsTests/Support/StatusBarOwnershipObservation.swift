#if canImport(UIKit)
import UIKit

/// window に直接重ねる器 (Loading / Toast) の表示中に、ステータスバーの見えを決める画面が
/// 提示元のままかを 1 回読む。
///
/// UIKit がステータスバーの見えを尋ねるのは、window の root から提示の連なり
/// (`presentedViewController`) と委ね先 (`childForStatusBarStyle` 等) をたどった先の画面である。
/// 器の View を window に重ねるだけなら、この連なりには何も加わらない。
/// 器が画面を提示する・親子関係に組み込む・root を差し替えると連なりが変わり、
/// 器の指定 (既定ではアイコンの明暗も表示/非表示も提示元と異なり得る) が採用され得る。
enum StatusBarOwnershipObservation {
    /// 器が取り付いていて、かつステータスバーの見えを決める画面が提示元のままなら落ち着いたと読む。
    @MainActor
    static func read(
        window: UIWindow,
        presenter: UIViewController,
        container: UIViewController?
    ) -> DialogTestWaiting.Reading {
        let attached = container?.view.window === window
        let rootIsPresenter = window.rootViewController === presenter
        let nothingPresented = presenter.presentedViewController == nil
        let noChildren = presenter.children.isEmpty
        let containerDetached = container?.parent == nil && container?.presentingViewController == nil
        let noDelegation = presenter.childForStatusBarStyle == nil && presenter.childForStatusBarHidden == nil
        return DialogTestWaiting.Reading(
            settled: attached && rootIsPresenter && nothingPresented && noChildren
                && containerDetached && noDelegation,
            "attached=\(attached) rootIsPresenter=\(rootIsPresenter) nothingPresented=\(nothingPresented) "
                + "noChildren=\(noChildren) containerDetached=\(containerDetached) noDelegation=\(noDelegation)"
        )
    }
}
#endif
