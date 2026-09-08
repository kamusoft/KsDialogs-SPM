#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// SwiftUI の中身を器に載せて window へ出し、実効値が固定されるところまで進める。
///
/// 添付値は SwiftUI の更新の中で届くため、同期解決しなかった場合は器が追加のレイアウトパスを
/// 挟んでから固定する。測るのはその固定が済んだあとでなければならない。
@MainActor
enum DialogSwiftUIMeasurement {
    /// 実効値の固定まで進んだ器と window。呼び出し側が使い終わるまで保持して自分で隠す。
    static func layoutInWindow<Content: View>(
        content: Content,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets,
        resultChannel: DialogResultChannel = DialogResultChannel()
    ) async throws -> (container: DialogContainerViewController, window: UIWindow) {
        let stage = DialogLayoutMeasurement.layoutInWindow(
            content: DialogSwiftUIHost.makeContent(content),
            showPlacement: showPlacement,
            screen: screen,
            insets: insets,
            resultChannel: resultChannel
        )
        let frozen = await DialogTestWaiting.waitUntil { stage.container.isLayoutSnapshotFrozen }
        try #require(frozen, "実効値が固定されなかった")
        stage.window.layoutIfNeeded()
        return stage
    }

    /// 実効値の固定まで進めたあとの中身の矩形 (window 座標)。
    static func measureContentFrame<Content: View>(
        content: Content,
        showPlacement: DialogPlacement? = nil,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) async throws -> CGRect {
        let stage = try await layoutInWindow(
            content: content,
            showPlacement: showPlacement,
            screen: screen,
            insets: insets
        )
        defer { stage.window.isHidden = true }
        return stage.container.contentView.frame
    }
}
#endif
