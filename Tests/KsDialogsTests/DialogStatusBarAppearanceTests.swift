#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// ダイアログの表示が、提示元の画面のステータスバー表示状態を変えないことを確かめる。
///
/// UIKit がステータスバーの見えを尋ねる相手は、全画面でない提示では
/// `modalPresentationCapturesStatusBarAppearance` が true の提示先だけである。
/// 器はこれを既定 (false) のままにしているため、制御は提示元に残る。
@Suite("ステータスバー表示状態の非干渉", .serialized)
@MainActor
struct DialogStatusBarAppearanceTests {
    @Test("[PB-IA-03] ステータスバー非表示の画面でダイアログを出しても再出現しない")
    func PB_IA_03_dialogDoesNotTakeOverStatusBarAppearance() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let presenter = StatusBarHiddenTestViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try #require(presenter.prefersStatusBarHidden, "提示元がステータスバーを非表示にしている前提")

        let surface = UIKitDialogPresentationSurface(
            keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
        )
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: DialogResultChannel()
        )
        surface.present(container)

        try #require(container.presentingViewController === presenter, "器が提示元の上に重なっている")
        // 器は提示元を置き換えないので、ステータスバーの見えを決める画面は変わらない。
        #expect(presenter.view.window === window)
        #expect(container.modalPresentationStyle == .overFullScreen)
        // 器が制御を奪うと、器の既定 (非表示にしない) が採用されてステータスバーが再出現する。
        #expect(
            container.modalPresentationCapturesStatusBarAppearance == false,
            "器はステータスバーの制御を奪わない"
        )
        #expect(container.childForStatusBarHidden == nil, "器は制御を委ねる先も持たない")
    }
}
#endif
