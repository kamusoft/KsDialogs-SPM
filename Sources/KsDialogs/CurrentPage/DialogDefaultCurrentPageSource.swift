#if canImport(UIKit)
import UIKit

/// ライブラリが内蔵する既定の取得元。提示先ウィンドウの view controller 階層を辿ってページを決める。
///
/// root から present の連なりを先端まで辿り、そこから `UINavigationController` の先頭と
/// `UITabBarController` の選択中のタブへ、コンテナでなくなるまで降りる。
/// 届くのは UIKit のコンテナまでで、`UIHostingController` の内側 (SwiftUI の `TabView` /
/// `NavigationStack`) には降りない。SwiftUI の画面は modifier で名乗ってもらう (core/ADR-0038)。
@MainActor
struct DialogDefaultCurrentPageSource: DialogCurrentPageSource {
    private static let origin = "the view controller hierarchy"

    func lookUpPageRect(in window: UIWindow) -> DialogCurrentPageLookup {
        guard let root = window.rootViewController else {
            return .notFound(reason: "The window presenting the dialog has no root view controller.")
        }
        guard let page = Self.currentPageViewController(from: root) else {
            return .notFound(reason: "The view controller hierarchy has no page other than KsDialogs containers.")
        }
        guard page.isViewLoaded else {
            return .notFound(reason: "The view of the current page view controller is not loaded.")
        }
        return DialogCurrentPageGeometry.pageRect(of: page.view, in: window, origin: Self.origin)
    }

    /// root から辿った表示中のページの view controller。
    ///
    /// present の連なりの途中にある KsDialogs 自身の器 (表示中のダイアログ・Loading・Toast) は
    /// ページに選ばず通り抜ける。器の上にさらに別の画面が present されていればその画面、
    /// 器しか無ければ器の提示元がページになる。閉じる途中の画面から先は辿らない
    /// (提示先の決め方と同じ扱い)。
    static func currentPageViewController(from root: UIViewController) -> UIViewController? {
        var page: UIViewController? = isKsDialogsContainer(root) ? nil : root
        var current = root
        while let presented = current.presentedViewController {
            if presented.isBeingDismissed { break }
            current = presented
            if !isKsDialogsContainer(presented) {
                page = presented
            }
        }
        return page.map(descendIntoContainers)
    }

    /// ナビゲーションとタブのコンテナを、表示中の子へ降りきる。
    private static func descendIntoContainers(_ viewController: UIViewController) -> UIViewController {
        var current = viewController
        while true {
            if let navigation = current as? UINavigationController, let top = navigation.topViewController {
                current = top
            } else if let tab = current as? UITabBarController, let selected = tab.selectedViewController {
                current = selected
            } else {
                return current
            }
        }
    }

    /// KsDialogs 自身が画面に出す器か。
    private static func isKsDialogsContainer(_ viewController: UIViewController) -> Bool {
        viewController is DialogContainerViewController
            || viewController is LoadingContainerViewController
            || viewController is ToastContainerViewController
    }
}
#endif
