#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// レジストリ・取り付け先・`Toast` を組み立てて、表示中のリストと器の取り付きを観察できるようにする。
///
/// 取り付け先は `DialogLayoutTestWindow` なので、共通ケース表と同じくシステム領域の余白を
/// 入力として与えられ、`changeGeometry` で回転・リサイズも起こせる。
/// 同じ取り付け先に載る `Loading` も併せて用意するので、機能間の前後関係も観察できる。
@MainActor
final class ToastTestHarness {
    /// 既定の取り付け先の寸法 (縦向き)。
    static let portraitScreen = DialogLayoutCase.Size(w: 390, h: 844)
    /// 既定の取り付け先のシステム領域の余白 (縦向き)。
    static let portraitInsets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)

    let window: DialogLayoutTestWindow
    let registry = ToastViewRegistry()
    let surface: ToastTestPresentationSurface
    let announcer = ToastTestAnnouncer()
    let coordinator: ToastCoordinator
    let toast: Toast

    /// 同じ取り付け先に載る Loading。機能間の前後関係の観察に使う。
    let loadingCoordinator: LoadingCoordinator
    let loading: Loading

    /// - Parameters:
    ///   - screen: 取り付け先の寸法
    ///   - insets: システム領域が占める4辺の余白
    ///   - hasHost: false にすると取り付け先が存在しない状況になる
    init(
        screen: DialogLayoutCase.Size = ToastTestHarness.portraitScreen,
        insets: DialogLayoutCase.Insets = ToastTestHarness.portraitInsets,
        hasHost: Bool = true
    ) {
        window = DialogLayoutTestWindow(frame: CGRect(x: 0, y: 0, width: screen.w, height: screen.h))
        window.simulatedSafeAreaInsets = UIEdgeInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
        window.rootViewController = UIViewController()
        window.isHidden = false
        surface = ToastTestPresentationSurface(hostView: hasHost ? window : nil)
        coordinator = ToastCoordinator(
            registry: registry,
            settings: ToastSettings(),
            presentationSurface: surface,
            announcer: announcer
        )
        toast = Toast(coordinator: coordinator)
        loadingCoordinator = LoadingCoordinator(
            registry: LoadingViewRegistry(),
            settings: LoadingSettings(),
            presentationSurface: LoadingTestPresentationSurface(hostView: window)
        )
        loading = Loading(coordinator: loadingCoordinator)
    }

    /// 取り付け先に重なっている Toast の器の View。並びは重なり順 (後ろほど手前)。
    var attachedContainerViews: [UIView] {
        window.subviews.filter { $0 is ToastContainerRootView }
    }

    /// 表示中の Toast の枚数 (取り付け先待ちのものを含む)。
    var displayCount: Int {
        coordinator.displayCount
    }

    /// 取り付け済みの器に載っている中身の View。並びは起動順。
    var contentViews: [UIView] {
        coordinator.presentedContentViews
    }

    /// 取り付け済みの器。並びは起動順。
    var containers: [ToastContainerViewController] {
        coordinator.presentedContainers
    }

    /// 表示中のデフォルト View。
    var defaultContentViews: [ToastDefaultContentView] {
        contentViews.compactMap { $0 as? ToastDefaultContentView }
    }

    /// 受理の待ち行列がはけるまで待つ。
    func drainAcceptance() async {
        await coordinator.acceptanceQueue.drain()
    }

    /// 指定した枚数の器が取り付くまで待つ。
    func waitUntilPresenting(count: Int = 1) async -> Bool {
        await DialogTestWaiting.waitUntil { self.containers.count == count }
    }

    /// 表示が全て消えるまで待つ。
    func waitUntilEmpty(timeout: Duration = .seconds(5)) async -> Bool {
        await DialogTestWaiting.waitUntil(timeout: timeout) { self.displayCount == 0 }
    }

    /// 取り付け先の寸法とシステム領域の余白を変え、その状態でレイアウトを走らせる。
    func changeGeometry(screen: DialogLayoutCase.Size, insets: DialogLayoutCase.Insets) {
        window.changeGeometry(screen: screen, insets: insets)
        window.layoutIfNeeded()
    }

    /// 取り付け先を片付ける。
    func tearDown() {
        window.isHidden = true
    }
}
#endif
