#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Loading の表示が、提示元の画面のステータスバーの指定 (アイコンの明暗・表示/非表示) を
/// 変えないことを確かめる (core/ADR-0040)。
///
/// Loading の器は key window に View を重ねるだけで、画面の提示も親子関係への組み込みもしない。
/// そのため UIKit がステータスバーの見えを尋ねる相手は、表示中も提示元のままである。
/// 取り付け先は既定の面 `KeyWindowLoadingPresentationSurface` で解決させ、実際の経路を通す。
/// 判定するのは見えを決める画面であって、実際に描かれた文字色ではない。
@Suite("Loading のステータスバーの指定の非干渉", .serialized)
@MainActor
struct LoadingStatusBarAppearanceTests {
    @Test("[LD-SB-01] 明るい地向けの明暗を指定した画面で Loading を出しても、明暗の指定は変わらない")
    func LD_SB_01_loadingKeepsPresenterStatusBarStyle() async throws {
        let presenter = StatusBarDarkContentTestViewController()
        try #require(presenter.preferredStatusBarStyle == .darkContent, "提示元がアイコンを明るい地向けに指定している前提")

        try await Self.expectLoadingKeepsStatusBarOwnership(presenter: presenter)
    }

    @Test("[LD-SB-02] バーを隠した画面で Loading を出しても、バーは隠れたまま")
    func LD_SB_02_loadingKeepsPresenterStatusBarHidden() async throws {
        let presenter = StatusBarHiddenTestViewController()
        try #require(presenter.prefersStatusBarHidden, "提示元がステータスバーを非表示にしている前提")

        try await Self.expectLoadingKeepsStatusBarOwnership(presenter: presenter)
    }

    /// 提示元を root にした key window の上に既定ローディングを出し、表示中もステータスバーの見えを
    /// 決める画面が提示元のままであることを確かめる。
    ///
    /// Loading には表示期限が無く、閉じるまで器が載り続けるので、観測中に器が外れる競合は無い。
    /// 観測を終えたら判定の前に閉じ、判定の失敗で器を残さない。
    private static func expectLoadingKeepsStatusBarOwnership(presenter: UIViewController) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let coordinator = LoadingCoordinator(
            registry: LoadingViewRegistry(),
            settings: LoadingSettings(),
            presentationSurface: KeyWindowLoadingPresentationSurface(
                keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
            )
        )
        let loading = Loading(coordinator: coordinator)

        await loading.show()
        try #require(coordinator.isPresenting, "既定ローディングが取り付いている")

        let outcome = await DialogTestWaiting.awaitSettled {
            StatusBarOwnershipObservation.read(
                window: window,
                presenter: presenter,
                container: coordinator.presentedContainer
            )
        }
        await loading.hide()
        #expect(coordinator.isPresenting == false, "観測を終えた器は閉じている")

        #expect(
            outcome.settled,
            outcome.message("器が画面を提示せず、親子関係にも組み込まれず、window の root が提示元のままである")
        )
    }
}
#endif
