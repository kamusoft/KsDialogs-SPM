#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("提示起点の window の選択", .serialized)
@MainActor
struct ApplicationKeyWindowProviderTests {
    /// key window として選ばれ得る window を用意する。
    private func makeKeyWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        return window
    }

    @Test("前面でアクティブなシーンの key window が選ばれる")
    func keyWindowOfForegroundActiveSceneIsSelected() throws {
        let keyWindow = makeKeyWindow()
        defer { keyWindow.isHidden = true }
        let otherWindow = UIWindow(frame: keyWindow.frame)
        try #require(keyWindow.isKeyWindow)

        let selected = ApplicationKeyWindowProvider.selectKeyWindow(from: [
            DialogWindowSceneSnapshot(isForegroundActive: true, windows: [otherWindow, keyWindow])
        ])

        #expect(selected === keyWindow)
    }

    @Test("前面でアクティブでないシーンの window は選ばれない")
    func windowOfInactiveSceneIsNotSelected() {
        let keyWindow = makeKeyWindow()
        defer { keyWindow.isHidden = true }

        let selected = ApplicationKeyWindowProvider.selectKeyWindow(from: [
            DialogWindowSceneSnapshot(isForegroundActive: false, windows: [keyWindow])
        ])

        #expect(selected == nil)
    }

    @Test("key window が無ければ選ばれない")
    func withoutKeyWindowNothingIsSelected() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        let selected = ApplicationKeyWindowProvider.selectKeyWindow(from: [
            DialogWindowSceneSnapshot(isForegroundActive: true, windows: [window])
        ])

        #expect(selected == nil)
    }

    @Test("シーンが無ければ選ばれない")
    func withoutScenesNothingIsSelected() {
        #expect(ApplicationKeyWindowProvider.selectKeyWindow(from: []) == nil)
    }
}
#endif
