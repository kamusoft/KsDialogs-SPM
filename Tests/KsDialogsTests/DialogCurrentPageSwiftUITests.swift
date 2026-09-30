#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// SwiftUI の `markAsDialogCurrentPage()` を通した「表示中のページ」を確かめる。
///
/// modifier は付けた View が画面に載ったときに台帳へ載る。SwiftUI の描画は非同期に進むため、
/// 台帳にこのウィンドウの候補が現れるまで待ってから器を重ねる。
@Suite("基準領域「表示中のページ」 (SwiftUI の modifier)", .serialized)
@MainActor
struct DialogCurrentPageSwiftUITests {
    private typealias Stage = DialogCurrentPageStage

    /// 台帳にこのウィンドウの候補が現れる (または消える) まで待つ。
    private func waitForLedger(in window: UIWindow, hasCandidate: Bool) async -> Bool {
        await DialogTestWaiting.waitUntil {
            window.layoutIfNeeded()
            let found: Bool
            if case .found = DialogCurrentPageLedger.shared.lookUpPageRect(in: window) {
                found = true
            } else {
                found = false
            }
            return found == hasCandidate
        }
    }

    /// 台帳が今このウィンドウについて返す矩形。
    private func ledgerRect(in window: UIWindow) throws -> CGRect {
        guard case .found(let rect) = DialogCurrentPageLedger.shared.lookUpPageRect(in: window) else {
            throw LedgerCandidateMissing()
        }
        return rect
    }

    /// View 階層から最初に見つかった指定の型の View。
    private func firstSubview<T: UIView>(of type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstSubview(of: type, in: subview) { return match }
        }
        return nil
    }

    @Test("SwiftUI の TabView + NavigationStack で content 枠の modifier が基準になり、タブバーとナビゲーションバーを避ける")
    func swiftUITabViewAndNavigationStackUseModifier() async throws {
        let window = Stage.makeWindow(
            rootViewController: UIHostingController(rootView: CurrentPageSwiftUITabHostView())
        )
        defer { window.isHidden = true }
        try #require(await waitForLedger(in: window, hasCandidate: true), "modifier の枠が台帳に載らない")
        let tabBar = try #require(firstSubview(of: UITabBar.self, in: window), "TabView のタブバーが見つからない")
        let navigationBar = try #require(
            firstSubview(of: UINavigationBar.self, in: window),
            "NavigationStack のナビゲーションバーが見つからない"
        )
        let tabBarTop = tabBar.convert(tabBar.bounds, to: nil).minY
        let navigationBarBottom = navigationBar.convert(navigationBar.bounds, to: nil).maxY

        let endEnd = Stage.showDialog(in: window, placement: Stage.endEnd)
        #expect(
            abs(endEnd.contentView.frame.maxY - (tabBarTop - Stage.margin)) <= 1,
            "下端はタブバーの上端から余白ぶん内側 (実測 \(endEnd.contentView.frame) / タブバー上端 \(tabBarTop))"
        )

        let startStart = Stage.showDialog(in: window, placement: Stage.startStart)
        #expect(
            abs(startStart.contentView.frame.minY - (navigationBarBottom + Stage.margin)) <= 1,
            "上端側はナビゲーションバーの下端から余白ぶん内側 (実測 \(startStart.contentView.frame) / バー下端 \(navigationBarBottom))"
        )
    }

    @Test("TabView の切り替え中に去るタブの印が残っていても、表示中のタブの印が基準になる")
    func swiftUITabViewUsesMarkerOfShownTabDuringSwitch() async throws {
        let host = CurrentPageSwiftUITabSwitchHost()
        let window = Stage.makeWindow(rootViewController: host)
        defer { window.isHidden = true }
        let arrivingRect = Stage.safeAreaRect(of: host.arrivingTab.view)
        // 両方のタブの枠が画面に載り、入れ子の内側 (去るタブの枠) が選ばれる状態になるまで待つ。
        let bothPlaced = await DialogTestWaiting.waitUntil {
            window.layoutIfNeeded()
            guard firstSubview(of: DialogCurrentPageMarkerView.self, in: host.arrivingTab.view)?.window === window,
                  firstSubview(of: DialogCurrentPageMarkerView.self, in: host.leavingTab.view)?.window === window,
                  case .found(let rect) = DialogCurrentPageLedger.shared.lookUpPageRect(in: window)
            else { return false }
            return arrivingRect.contains(rect) && rect != arrivingRect
        }
        try #require(bothPlaced, "去るタブの枠が来るタブの枠の内側に載らない")

        host.beginCrossFade()

        #expect(try ledgerRect(in: window) == arrivingRect, "表示中 (来るタブ) の枠が基準になる")
        let startStart = Stage.showDialog(in: window, placement: Stage.startStart)
        Stage.expectFrame(startStart.contentView, Stage.startStartFrame(in: arrivingRect), "表示中のタブの枠")
    }

    @Test("既定の取得元が届く UIKit の画面でも、modifier を付けた枠が既定に勝つ。枠が画面から外れると既定に戻る")
    func modifierWinsOverDefaultAndFallsBackAfterDetach() async throws {
        let host = DialogCurrentPageTabHost(
            firstPage: UIHostingController(rootView: CurrentPageSwiftUIFrameView())
        )
        defer { host.tearDown() }
        try #require(await waitForLedger(in: host.window, hasCandidate: true), "modifier の枠が台帳に載らない")
        let markedRect = try ledgerRect(in: host.window)
        try #require(
            abs(markedRect.height - CurrentPageSwiftUIFrameView.markedHeight) <= 1,
            "台帳の矩形は modifier を付けた枠 (実測 \(markedRect))"
        )

        let marked = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        Stage.expectFrame(marked.contentView, Stage.endEndFrame(in: markedRect), "modifier を付けた枠")

        // 別のタブへ切り替えると、付けた枠は画面から外れる。
        host.selectTab(1)
        try #require(await waitForLedger(in: host.window, hasCandidate: false), "画面から外れた枠が台帳に残っている")

        let afterDetach = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        Stage.expectFrame(
            afterDetach.contentView,
            Stage.endEndFrame(in: Stage.safeAreaRect(of: host.secondPage.view)),
            "既定の取得元 (選択中のタブ)"
        )

        // 戻る遷移で枠が再び配置されると、また枠が基準になる。
        host.selectTab(0)
        try #require(await waitForLedger(in: host.window, hasCandidate: true), "戻った枠が台帳に載らない")
        let afterReturn = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        Stage.expectFrame(afterReturn.contentView, Stage.endEndFrame(in: try ledgerRect(in: host.window)), "戻った枠")
    }

    @Test("modifier の台帳が登録した provider に勝ち、台帳が空になると登録した provider へ進む")
    func ledgerWinsOverRegisteredProviderThenFallsBack() async throws {
        let host = DialogCurrentPageTabHost(
            firstPage: UIHostingController(rootView: CurrentPageSwiftUIFrameView())
        )
        defer { host.tearDown() }
        // タブを切り替えても画面に残り続ける View を provider が返す。
        let providedView = UIView(frame: CGRect(x: 20, y: 250, width: 360, height: 300))
        providedView.isUserInteractionEnabled = false
        host.tabBarController.view.addSubview(providedView)
        DialogCurrentPage.provider = { providedView }
        defer { DialogCurrentPage.provider = nil }
        try #require(await waitForLedger(in: host.window, hasCandidate: true), "modifier の枠が台帳に載らない")

        let withLedger = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        Stage.expectFrame(withLedger.contentView, Stage.endEndFrame(in: try ledgerRect(in: host.window)), "台帳の枠")

        host.selectTab(1)
        try #require(await waitForLedger(in: host.window, hasCandidate: false), "画面から外れた枠が台帳に残っている")

        let withoutLedger = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        Stage.expectFrame(
            withoutLedger.contentView,
            Stage.endEndFrame(in: Stage.safeAreaRect(of: providedView)),
            "登録した provider の View"
        )
    }
}

/// 台帳にこのウィンドウの候補が無かったことを表すエラー。
private struct LedgerCandidateMissing: Error {}
#endif
