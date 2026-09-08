#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// レジストリ・取り付け先・`Loading` を組み立てて、合流状態と器の取り付きを観察できるようにする。
///
/// 取り付け先は `DialogLayoutTestWindow` なので、共通ケース表と同じくシステム領域の余白を
/// 入力として与えられ、`changeGeometry` で回転・リサイズも起こせる。
@MainActor
final class LoadingTestHarness {
    /// 既定の取り付け先の寸法 (縦向き)。
    static let portraitScreen = DialogLayoutCase.Size(w: 390, h: 844)
    /// 既定の取り付け先のシステム領域の余白 (縦向き)。
    static let portraitInsets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)

    let window: DialogLayoutTestWindow
    let registry = LoadingViewRegistry()
    let surface: LoadingTestPresentationSurface
    let coordinator: LoadingCoordinator
    let loading: Loading

    /// - Parameters:
    ///   - screen: 取り付け先の寸法
    ///   - insets: システム領域が占める4辺の余白
    ///   - hasHost: false にすると取り付け先が存在しない状況になる
    init(
        screen: DialogLayoutCase.Size = LoadingTestHarness.portraitScreen,
        insets: DialogLayoutCase.Insets = LoadingTestHarness.portraitInsets,
        hasHost: Bool = true
    ) {
        window = DialogLayoutTestWindow(frame: CGRect(x: 0, y: 0, width: screen.w, height: screen.h))
        window.simulatedSafeAreaInsets = UIEdgeInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
        // 回転の再現 (changeGeometry) は root の View を基準に可視領域を計算し直すため、
        // Loading を root へ載せない構成でも root は必要になる。
        window.rootViewController = UIViewController()
        window.isHidden = false
        surface = LoadingTestPresentationSurface(hostView: hasHost ? window : nil)
        coordinator = LoadingCoordinator(
            registry: registry,
            settings: LoadingSettings(),
            presentationSurface: surface
        )
        loading = Loading(coordinator: coordinator)
    }

    /// 取り付け先に重なっている Loading の器の View。
    /// 取り付け先には root の中身や提示中のダイアログも載るため、器の View だけを拾う。
    var attachedContainerViews: [UIView] {
        window.subviews.filter { $0 is LoadingContainerRootView }
    }

    /// 器が取り付いているか。
    var isPresenting: Bool {
        coordinator.isPresenting
    }

    /// 表示中の中身の View。
    var contentView: UIView? {
        coordinator.presentedContentView
    }

    /// 表示中の既定ローディングの表示テキスト。
    var builtinText: String? {
        coordinator.presentedBuiltinContentView?.displayedText
    }

    /// 表示中の器の View。
    var containerView: UIView? {
        coordinator.presentedContainer?.view
    }

    /// 器が取り付くまで待つ。
    func waitUntilPresenting() async -> Bool {
        await DialogTestWaiting.waitUntil { self.isPresenting }
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
