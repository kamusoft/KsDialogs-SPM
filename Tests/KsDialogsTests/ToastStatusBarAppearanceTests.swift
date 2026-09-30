#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Toast の表示が、提示元の画面のステータスバーの指定 (アイコンの明暗・表示/非表示) を
/// 変えないことを確かめる (core/ADR-0040)。
///
/// Toast の器は key window に View を重ねるだけで、画面の提示も親子関係への組み込みもしない。
/// そのため UIKit がステータスバーの見えを尋ねる相手は、表示中も提示元のままである。
/// 取り付け先は既定の面 `KeyWindowToastPresentationSurface` で解決させ、実際の経路を通す。
/// 判定するのは見えを決める画面であって、実際に描かれた文字色ではない。
@Suite("Toast のステータスバーの指定の非干渉", .serialized)
@MainActor
struct ToastStatusBarAppearanceTests {
    /// 器の取り付きを待つ上限。
    private static let attachTimeout = Duration.seconds(5)

    /// 見えを決める画面の落ち着きを待つ上限。
    private static let settleTimeout = Duration.seconds(5)

    /// 表示期限 (ミリ秒)。取り付け待ちと落ち着き待ちの上限を合わせた 10 秒に、安定の観測時間と
    /// 負荷による遅れの余裕を足しても届かない長さにする。観測中に正常な Toast が期限で消えると、
    /// 器が外れたことをステータスバーの退行と読み違えるため。
    private static let displayDuration = 30_000

    @Test("[TS-SB-01] 明るい地向けの明暗を指定した画面で Toast を出しても、明暗の指定は変わらない")
    func TS_SB_01_toastKeepsPresenterStatusBarStyle() async throws {
        let presenter = StatusBarDarkContentTestViewController()
        try #require(presenter.preferredStatusBarStyle == .darkContent, "提示元がアイコンを明るい地向けに指定している前提")

        try await Self.expectToastKeepsStatusBarOwnership(presenter: presenter)
    }

    @Test("[TS-SB-02] バーを隠した画面で Toast を出しても、バーは隠れたまま")
    func TS_SB_02_toastKeepsPresenterStatusBarHidden() async throws {
        let presenter = StatusBarHiddenTestViewController()
        try #require(presenter.prefersStatusBarHidden, "提示元がステータスバーを非表示にしている前提")

        try await Self.expectToastKeepsStatusBarOwnership(presenter: presenter)
    }

    /// 提示元を root にした key window の上にメッセージ入口で Toast を出し、表示中もステータスバーの
    /// 見えを決める画面が提示元のままであることを確かめる。
    ///
    /// Toast には閉じる口が無いため、観測を終えたら coordinator の後始末 (`discardAll()`) で表示ごと捨てる。
    /// 途中で打ち切られた回も同じ後始末を通し、長い表示期限のまま器・表示・期限の計時を残さない。
    private static func expectToastKeepsStatusBarOwnership(presenter: UIViewController) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let coordinator = ToastCoordinator(
            registry: ToastViewRegistry(),
            settings: ToastSettings(),
            presentationSurface: KeyWindowToastPresentationSurface(
                keyWindowProvider: DialogTestKeyWindowProvider(keyWindow: window)
            ),
            announcer: ToastTestAnnouncer()
        )
        let toast = Toast(coordinator: coordinator)
        defer { coordinator.discardAll() }

        let shownAt = ContinuousClock.now
        toast.show(message: "ステータスバーの確認", duration: displayDuration)
        let attached = await DialogTestWaiting.waitUntil(timeout: attachTimeout) {
            coordinator.presentedContainers.count == 1
        }
        let container = try #require(
            attached ? coordinator.presentedContainers.first : nil,
            "Toast の器が取り付いている"
        )

        let outcome = await DialogTestWaiting.awaitSettled(timeout: settleTimeout) {
            StatusBarOwnershipObservation.read(window: window, presenter: presenter, container: container)
        }
        let elapsed = shownAt.duration(to: .now)
        let stillDisplayed = coordinator.displayCount == 1

        // 期限による撤去が先に始まっていた回も含め、判定の前に表示ごと捨てる。
        coordinator.discardAll()
        #expect(coordinator.displayCount == 0, "観測を終えた表示は残っていない")
        #expect(container.view.window == nil, "観測を終えた器は取り付け先から外れている")

        // 期限切れで器が外れた回は、ステータスバーの判定とは別の失敗として報告する。
        try #require(
            elapsed < .milliseconds(displayDuration) && stillDisplayed,
            "判定の時点で Toast は期限前で表示中である (経過 \(elapsed))"
        )
        #expect(
            outcome.settled,
            outcome.message("器が画面を提示せず、親子関係にも組み込まれず、window の root が提示元のままである")
        )
    }
}
#endif
