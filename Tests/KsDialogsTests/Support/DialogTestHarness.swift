#if canImport(UIKit)

@testable import KsDialogs

/// レジストリ・提示面・`Dialog` を組み立てて、show の結果と器の重なりを観察できるようにする。
@MainActor
final class DialogTestHarness {
    let registry: DialogViewRegistry
    let presentationSurface = DialogTestPresentationSurface()
    let dialogs: Dialog

    /// - Parameters:
    ///   - registry: 使用するレジストリ。既定は他のテストと干渉しない新規レジストリ
    ///   - hasPresentationHost: false にすると提示先が存在しない状況になる
    init(registry: DialogViewRegistry = DialogViewRegistry(), hasPresentationHost: Bool = true) {
        self.registry = registry
        presentationSurface.isPresentationHostAvailable = hasPresentationHost
        dialogs = Dialog(registry: registry, presentationSurface: presentationSurface)
    }

    /// 提示されているダイアログの器を、下から順に並べたもの。
    var presentedContainers: [DialogContainerViewController] {
        presentationSurface.presentedContainers
    }

    /// 一番手前のダイアログの器。
    var topmostContainer: DialogContainerViewController? {
        presentedContainers.last
    }

    /// ダイアログが指定枚数提示されるまで待つ。
    func waitForPresentedContainers(count: Int) async -> Bool {
        await DialogTestWaiting.waitUntil { self.presentedContainers.count == count }
    }
}
#endif
