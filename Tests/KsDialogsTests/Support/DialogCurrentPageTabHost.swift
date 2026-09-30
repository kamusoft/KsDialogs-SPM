#if canImport(UIKit)
import UIKit

/// UIKit のタブ + ナビゲーションで組んだテスト用の画面。
///
/// 1 つ目のタブは `UINavigationController` で、その先頭の view controller がページになる。
/// 2 つ目のタブは素の view controller。ページの View はどちらもバーの下まで伸び、
/// safe area がバーの内側になる (UIKit 標準の形)。
@MainActor
final class DialogCurrentPageTabHost {
    let window: DialogLayoutTestWindow
    let tabBarController: UITabBarController
    let navigationController: UINavigationController
    /// 1 つ目のタブのナビゲーションの先頭。
    let firstPage: UIViewController
    /// 2 つ目のタブ。
    let secondPage: UIViewController

    /// - Parameter firstPage: 1 つ目のタブのナビゲーションの先頭に置く view controller。nil なら素のものを使う
    init(firstPage: UIViewController? = nil) {
        let firstPage = firstPage ?? UIViewController()
        firstPage.title = "First"
        let secondPage = UIViewController()
        secondPage.title = "Second"
        let navigationController = UINavigationController(rootViewController: firstPage)
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [navigationController, secondPage]
        self.firstPage = firstPage
        self.secondPage = secondPage
        self.navigationController = navigationController
        self.tabBarController = tabBarController
        self.window = DialogCurrentPageStage.makeWindow(rootViewController: tabBarController)
    }

    /// タブバーの矩形 (ウィンドウ座標)。
    var tabBarFrame: CGRect {
        tabBarController.tabBar.convert(tabBarController.tabBar.bounds, to: nil)
    }

    /// ナビゲーションバーの矩形 (ウィンドウ座標)。
    var navigationBarFrame: CGRect {
        navigationController.navigationBar.convert(navigationController.navigationBar.bounds, to: nil)
    }

    /// 選択中のタブを切り替え、そのレイアウトまで進める。
    func selectTab(_ index: Int) {
        tabBarController.selectedIndex = index
        window.layoutIfNeeded()
    }

    func tearDown() {
        window.isHidden = true
    }
}
#endif
