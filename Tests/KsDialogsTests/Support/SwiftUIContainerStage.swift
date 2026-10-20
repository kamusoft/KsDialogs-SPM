#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// SwiftUI の中身を Loading・Toast の器に載せて window へ重ね、実効値の固定まで進める。
///
/// Dialog の器は `DialogSwiftUIMeasurement` が受け持つ。window を隠すと表示状態が終わるため、
/// 呼び出し側が使い終わるまで保持して自分で隠す。
@MainActor
enum SwiftUIContainerStage {
    static func loading<Content: View>(
        content: Content,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) async throws -> (container: LoadingContainerViewController, window: DialogLayoutTestWindow) {
        let window = makeWindow(screen: screen, insets: insets)
        let container = LoadingContainerViewController(
            content: DialogSwiftUIHost.makeContent(content),
            placement: showPlacement
        )
        container.attach(to: window)
        let frozen = await DialogTestWaiting.waitUntil { container.isLayoutSnapshotFrozen }
        try #require(frozen, "実効値が固定されなかった")
        window.layoutIfNeeded()
        return (container, window)
    }

    static func toast<Content: View>(
        content: Content,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) async throws -> (container: ToastContainerViewController, window: DialogLayoutTestWindow) {
        let window = makeWindow(screen: screen, insets: insets)
        let container = ToastContainerViewController(
            content: DialogSwiftUIHost.makeContent(content),
            placement: showPlacement,
            fallbackPlacement: ToastPlacementDefault.placement
        )
        container.attach(to: window)
        let frozen = await DialogTestWaiting.waitUntil { container.isLayoutSnapshotFrozen }
        try #require(frozen, "実効値が固定されなかった")
        window.layoutIfNeeded()
        return (container, window)
    }

    private static func makeWindow(
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) -> DialogLayoutTestWindow {
        let window = DialogLayoutTestWindow(frame: CGRect(x: 0, y: 0, width: screen.w, height: screen.h))
        window.simulatedSafeAreaInsets = UIEdgeInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
        window.rootViewController = UIViewController()
        window.isHidden = false
        return window
    }
}
#endif
