#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 基準領域「表示中のページ」を UIKit の画面で確かめる。
///
/// 既定の取得元 (view controller 階層の走査)・登録した関数による上書き・取得元の優先順位・
/// 未解決時の可視領域への落ち方・表示中のウィンドウ変化での問い合わせ直しを扱う。
/// SwiftUI の modifier は `DialogCurrentPageSwiftUITests`、台帳の規則は `DialogCurrentPageLedgerTests` が扱う。
@Suite("基準領域「表示中のページ」 (UIKit)", .serialized)
@MainActor
struct DialogCurrentPageTests {
    private typealias Stage = DialogCurrentPageStage

    /// 登録の口はアプリ全体で 1 つなので、各テストの終わりに必ず外す。
    private func withRegisteredProvider(
        _ provider: (@MainActor () throws -> UIView?)?,
        _ body: () -> Void
    ) {
        DialogCurrentPage.provider = provider
        defer { DialogCurrentPage.provider = nil }
        body()
    }

    // MARK: 基準領域の意味

    @Test("tab + navigation の画面で End 配置がタブバーを避け、上端側はナビゲーションバーの下端を基準にする")
    func tabAndNavigationEndPlacementAvoidsTabBar() throws {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }
        let page = Stage.safeAreaRect(of: host.firstPage.view)
        try #require(page.maxY <= host.tabBarFrame.minY + 0.5, "ページの safe area はタブバーの上で終わる")
        try #require(host.firstPage.view.frame.maxY > page.maxY, "ページの View 自体はタブバーの下まで伸びている")

        let endEnd = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        defer { endEnd.container.view.removeFromSuperview() }
        Stage.expectFrame(endEnd.contentView, Stage.endEndFrame(in: page), "End/End")
        #expect(
            abs(endEnd.contentView.frame.maxY - (host.tabBarFrame.minY - Stage.margin)) <= 1,
            "下端はタブバーの上端から余白ぶん内側"
        )

        let startStart = Stage.showDialog(in: host.window, placement: Stage.startStart)
        defer { startStart.container.view.removeFromSuperview() }
        #expect(
            abs(startStart.contentView.frame.minY - (host.navigationBarFrame.maxY + Stage.margin)) <= 1,
            "上端側はナビゲーションバーの下端から余白ぶん内側"
        )
    }

    @Test("同じ画面で visibleArea はタブバーに重なり、currentPage よりタブバーの高さぶん下に出る")
    func visibleAreaOverlapsTabBarOnSameScreen() {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }

        let currentPage = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        let visibleArea = Stage.showDialog(in: host.window, layoutArea: .visibleArea, placement: Stage.endEnd)

        Stage.expectFrame(visibleArea.contentView, Stage.endEndFrame(in: Stage.visibleRect), "visibleArea")
        let pageBottomGap = Stage.visibleRect.maxY - Stage.safeAreaRect(of: host.firstPage.view).maxY
        #expect(pageBottomGap > 0, "タブバーが可視領域の下部を占めている")
        #expect(
            abs((visibleArea.contentView.frame.minY - currentPage.contentView.frame.minY) - pageBottomGap) <= 1,
            "差はタブバーが可視領域を占める高さに等しい"
        )
        #expect(visibleArea.contentView.frame.maxY > host.tabBarFrame.minY, "visibleArea の結果はタブバーに重なる")
    }

    @Test("タブ・ナビゲーションを持たない全画面のページでは visibleArea と一致する")
    func fullScreenPageMatchesVisibleArea() {
        let window = Stage.makeWindow(rootViewController: UIViewController())
        defer { window.isHidden = true }

        let currentPage = Stage.showDialog(in: window, placement: Stage.endEnd)
        let visibleArea = Stage.showDialog(in: window, layoutArea: .visibleArea, placement: Stage.endEnd)

        Stage.expectFrame(currentPage.contentView, visibleArea.contentView.frame, "currentPage と visibleArea")
    }

    @Test("比率サイズはページの矩形 (タブバーを除く) を基準にする")
    func proportionalHeightUsesPageRect() {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }
        let page = Stage.safeAreaRect(of: host.firstPage.view)

        let shown = Stage.showDialog(
            in: host.window,
            placement: DialogPlacement(),
            proportionalHeight: 0.5
        )

        #expect(abs(shown.contentView.frame.height - page.height * 0.5) <= 1, "高さはページの高さの 5 割")
    }

    // MARK: 既定の取得元 (view controller 階層の走査)

    @Test("present された画面が現在ページになる")
    func presentedViewControllerBecomesCurrentPage() throws {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }
        let presented = UIViewController()
        host.tabBarController.present(presented, animated: false)
        try #require(host.tabBarController.presentedViewController === presented)
        // シーンを持たないテストランナーでは present の遷移が完走せず View が載らないため、
        // シート状の矩形で直接載せる (下側だけを占める画面)。
        presented.view.frame = CGRect(x: 0, y: 300, width: Stage.screen.w, height: Stage.screen.h - 300)
        host.window.addSubview(presented.view)
        host.window.layoutIfNeeded()
        let page = Stage.safeAreaRect(of: presented.view)
        try #require(page != Stage.safeAreaRect(of: host.firstPage.view), "present された画面とタブ画面を見分けられる")

        let shown = Stage.showDialog(in: host.window, placement: Stage.startStart)

        Stage.expectFrame(shown.contentView, Stage.startStartFrame(in: page), "present された画面の safe area")
    }

    @Test("表示中の器は現在ページにならず、背後のタブ画面の先端が基準になる")
    func presentedDialogContainerIsNotCurrentPage() throws {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }
        let page = Stage.safeAreaRect(of: host.firstPage.view)
        // 1 つ目のダイアログが提示の連なりに載っている状態 (器はページとして選ばれない)。
        let firstDialog = DialogContainerViewController(
            contentView: FixedContentSizeView(contentSize: Stage.contentSize),
            resultChannel: DialogResultChannel()
        )
        host.tabBarController.present(firstDialog, animated: false)
        try #require(host.tabBarController.presentedViewController === firstDialog)

        let second = Stage.showDialog(in: host.window, placement: Stage.endEnd)

        Stage.expectFrame(second.contentView, Stage.endEndFrame(in: page), "2 つ目の基準はタブ画面の先端")
        #expect(second.container.currentPageDiagnostics.isEmpty, "既定の取得元で解決している")
    }

    @Test("別ウィンドウの View を返す provider は使われず、既定の取得元の結果が基準になる")
    func viewInAnotherWindowIsNotUsed() {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }
        let otherWindow = Stage.makeWindow(rootViewController: UIViewController())
        defer { otherWindow.isHidden = true }
        let foreignView = UIView(frame: CGRect(x: 0, y: 200, width: 400, height: 300))
        otherWindow.addSubview(foreignView)

        withRegisteredProvider({ foreignView }) {
            let shown = Stage.showDialog(in: host.window, placement: Stage.endEnd)
            Stage.expectFrame(
                shown.contentView,
                Stage.endEndFrame(in: Stage.safeAreaRect(of: host.firstPage.view)),
                "既定の取得元 (タブ画面の先端)"
            )
        }
    }

    // MARK: 登録した provider

    @Test("登録した provider の View が既定より優先され、登録を外すと既定に戻る")
    func registeredProviderOverridesDefaultUntilCleared() throws {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }
        let customView = UIView(frame: CGRect(x: 20, y: 200, width: 360, height: 300))
        host.firstPage.view.addSubview(customView)
        let customRect = Stage.safeAreaRect(of: customView)
        let defaultRect = Stage.safeAreaRect(of: host.firstPage.view)
        try #require(customRect != defaultRect)

        withRegisteredProvider({ customView }) {
            let shown = Stage.showDialog(in: host.window, placement: Stage.endEnd)
            Stage.expectFrame(shown.contentView, Stage.endEndFrame(in: customRect), "登録した View の safe area")
        }

        // 登録を外した後の表示は既定の取得元に戻る。
        let shown = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        Stage.expectFrame(shown.contentView, Stage.endEndFrame(in: defaultRect), "既定の取得元")
    }

    @Test("登録の差し替えは次の表示から効き、表示中のダイアログは問い合わせ直しても元の登録を使う")
    func providerReplacementAppliesFromNextShow() throws {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }
        let viewA = UIView(frame: CGRect(x: 0, y: 400, width: 400, height: 250))
        let viewB = UIView(frame: CGRect(x: 0, y: 150, width: 400, height: 250))
        host.firstPage.view.addSubview(viewA)
        host.firstPage.view.addSubview(viewB)
        defer { DialogCurrentPage.provider = nil }

        DialogCurrentPage.provider = { viewA }
        let first = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        let expectedFirst = Stage.endEndFrame(in: Stage.safeAreaRect(of: viewA))
        Stage.expectFrame(first.contentView, expectedFirst, "差し替え前")

        DialogCurrentPage.provider = { viewB }
        // 可視領域の余白を変えて、表示中のダイアログに問い合わせ直しを起こす。
        host.window.changeGeometry(
            screen: Stage.screen,
            insets: DialogLayoutCase.Insets(top: 50, bottom: 31, left: 0, right: 0)
        )
        Stage.expectFrame(first.contentView, expectedFirst, "表示中のダイアログは差し替えの影響を受けない")

        let second = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        Stage.expectFrame(second.contentView, Stage.endEndFrame(in: Stage.safeAreaRect(of: viewB)), "次の表示")
    }

    @Test("登録した provider が nil を返すと既定の取得元へ進む")
    func nilProviderFallsBackToDefault() {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }

        withRegisteredProvider({ nil }) {
            let shown = Stage.showDialog(in: host.window, placement: Stage.endEnd)
            Stage.expectFrame(
                shown.contentView,
                Stage.endEndFrame(in: Stage.safeAreaRect(of: host.firstPage.view)),
                "既定の取得元"
            )
            #expect(shown.container.currentPageDiagnostics.isEmpty)
        }
    }

    @Test("登録した provider がエラーを投げると既定の取得元へ進む")
    func throwingProviderFallsBackToDefault() {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }

        withRegisteredProvider({ throw CurrentPageProbeError() }) {
            let shown = Stage.showDialog(in: host.window, placement: Stage.endEnd)
            Stage.expectFrame(
                shown.contentView,
                Stage.endEndFrame(in: Stage.safeAreaRect(of: host.firstPage.view)),
                "既定の取得元"
            )
        }
    }

    // MARK: 未解決

    @Test("既定の取得元も解決できないときは visibleArea と一致し、理由の診断が 1 件出る")
    func unresolvedFallsBackToVisibleAreaWithDiagnostic() {
        // 器そのものをウィンドウの root に載せると、器以外のページが存在しない。
        let contentView = FixedContentSizeView(contentSize: Stage.contentSize)
        contentView.ksDialogOptions = DialogOptions(layoutArea: .currentPage)
        contentView.ksDialogPlacement = Stage.endEnd
        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Stage.screen,
            insets: Stage.insets
        )
        defer { stage.window.isHidden = true }

        Stage.expectFrame(contentView, Stage.endEndFrame(in: Stage.visibleRect), "visibleArea と同じ位置")
        #expect(stage.container.currentPageDiagnostics.count == 1, "未解決の診断は 1 件")
        let diagnostic = stage.container.currentPageDiagnostics.first ?? ""
        #expect(diagnostic.hasPrefix("The current page could not be resolved, so the visible area is used instead."))
        #expect(diagnostic.contains("KsDialogs containers"), "既定の取得元が解決できなかった理由を含む")
    }

    @Test("provider が nil を返し既定の取得元も解決できないときは visibleArea と一致する")
    func nilProviderWithoutDefaultFallsBackToVisibleArea() {
        withRegisteredProvider({ nil }) {
            let contentView = FixedContentSizeView(contentSize: Stage.contentSize)
            contentView.ksDialogOptions = DialogOptions(layoutArea: .currentPage)
            contentView.ksDialogPlacement = Stage.endEnd
            let stage = DialogLayoutMeasurement.layoutInWindow(
                contentView: contentView,
                screen: Stage.screen,
                insets: Stage.insets
            )
            defer { stage.window.isHidden = true }

            Stage.expectFrame(contentView, Stage.endEndFrame(in: Stage.visibleRect), "visibleArea と同じ位置")
            #expect(stage.container.currentPageDiagnostics.first?.contains("returned nil") == true)
        }
    }

    @Test("provider がエラーを投げても表示は失敗せず、visibleArea の位置に出て結果は通常どおり返る")
    func throwingProviderDoesNotFailShow() async throws {
        DialogCurrentPage.provider = { throw CurrentPageProbeError() }
        defer { DialogCurrentPage.provider = nil }
        // テスト用の提示面は root を持たないウィンドウへ器を載せるため、既定の取得元も解決できない。
        let harness = DialogTestHarness()
        let recorder = DialogTestRecorder<Bool>()
        harness.registry.register(BasicTestDialogViewModel.self) { _, notifier in
            let view = FixedContentSizeView(contentSize: Stage.contentSize)
            view.ksDialogOptions = DialogOptions(layoutArea: .currentPage)
            view.ksDialogPlacement = Stage.endEnd
            recorder.record(view: view, notifier: notifier)
            return view
        }

        let showTask = Task { try await harness.dialogs.show(BasicTestDialogViewModel(message: "")) }
        let notifier = try await recorder.notifier(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))
        let container = try #require(harness.topmostContainer)
        let visibleArea = container.view.bounds.inset(by: container.view.safeAreaInsets)
        Stage.expectFrame(container.contentView, Stage.endEndFrame(in: visibleArea), "visibleArea")
        #expect(container.currentPageDiagnostics.first?.contains("threw an error") == true)

        notifier.complete(true)
        #expect(try await showTask.value == .completed(true))
    }

    // MARK: 表示中のウィンドウ変化

    @Test("[PB-WN-01] 回転でページの矩形が変わると、回転後のページを基準に再配置される")
    func PB_WN_01_rotationRequeriesCurrentPage() async throws {
        let host = DialogCurrentPageTabHost()
        defer { host.tearDown() }
        let shown = Stage.showDialog(in: host.window, placement: Stage.endEnd)
        let portraitPage = Stage.safeAreaRect(of: host.firstPage.view)
        Stage.expectFrame(shown.contentView, Stage.endEndFrame(in: portraitPage), "縦向き")

        let landscapeScreen = DialogLayoutCase.Size(w: 800, h: 400)
        let landscapeInsets = DialogLayoutCase.Insets(top: 0, bottom: 21, left: 59, right: 59)
        host.window.changeGeometry(screen: landscapeScreen, insets: landscapeInsets)

        let landscapePage = Stage.safeAreaRect(of: host.firstPage.view)
        try #require(landscapePage != portraitPage, "回転でページの矩形が変わっている")
        let landscapeVisible = CGRect(x: 59, y: 0, width: 800 - 118, height: 400 - 21)
        let expected = Stage.endEndFrame(in: landscapePage.intersection(landscapeVisible))
        // ページ側 (タブバーの高さ) の更新は回転と同じレイアウトパスで終わるとは限らず、
        // 器は同じ回転に対して次の main の番にもう一度問い合わせる。そこまで待って確かめる。
        _ = await DialogTestWaiting.waitUntil {
            abs(shown.contentView.frame.minX - expected.minX) <= 0.5
                && abs(shown.contentView.frame.minY - expected.minY) <= 0.5
        }
        Stage.expectFrame(shown.contentView, expected, "横向きのページ")
    }
}

/// 登録した関数がエラーを投げる状況を作るためのエラー。
private struct CurrentPageProbeError: Error {}
#endif
