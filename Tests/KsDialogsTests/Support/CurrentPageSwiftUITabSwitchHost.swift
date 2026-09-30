#if canImport(UIKit)
import KsDialogs
import SwiftUI
import UIKit

/// SwiftUI の `TabView` がタブを切り替える演出の途中の状態を、2 つのタブの画面で再現するテスト用の画面。
///
/// iOS 26 の実機相当 (Simulator) の実測では、`TabView` はタブを切り替えると去るタブの画面を
/// 演出が終わるまでウィンドウに残し、その間
///
/// - 去るタブ (ナビゲーションバーを持つ Panel) の画面は `alpha` が 0 で、見た目だけが 1 から下がっていく
/// - 来るタブ (タイトルバーを持たない Info) の画面は `alpha` が 1 で、見た目だけが 0 から上がっていく
///
/// という状態になる。テストのウィンドウはシーンに属さず `TabView` の切り替えが進まないため、
/// 同じ形を 2 つの `UIHostingController` を重ねて作る。どちらのタブも中身の枠に
/// `markAsDialogCurrentPage()` を付けており、去るタブの枠は来るタブの枠の内側にある (入れ子)。
@MainActor
final class CurrentPageSwiftUITabSwitchHost: UIViewController {
    /// 去るタブ。`NavigationStack` の中身の枠に modifier を付ける。
    let leavingTab = UIHostingController(rootView: CurrentPageSwiftUIPanelPage())

    /// 来るタブ。バーを持たない画面の中身の枠に modifier を付ける。
    let arrivingTab = UIHostingController(rootView: CurrentPageSwiftUIInfoPage())

    override func viewDidLoad() {
        super.viewDidLoad()
        let tabs: [UIViewController] = [leavingTab, arrivingTab]
        for tab in tabs {
            addChild(tab)
            tab.view.frame = view.bounds
            tab.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(tab.view)
            tab.didMove(toParent: self)
        }
    }

    /// 切り替えの演出の途中の状態にする。演出は十分長く取り、テストの間に終わらないようにする。
    func beginCrossFade() {
        leavingTab.view.alpha = 0
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = 60
        leavingTab.view.layer.add(fadeOut, forKey: "opacity")

        arrivingTab.view.alpha = 1
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = 60
        arrivingTab.view.layer.add(fadeIn, forKey: "opacity")
    }
}
#endif
