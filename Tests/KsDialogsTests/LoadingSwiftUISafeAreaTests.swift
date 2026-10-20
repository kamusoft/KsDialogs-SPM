#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// Loading の器に載せた SwiftUI の中身も、Dialog と同じホストを通って安全領域を受け取ることを確かめる。
@Suite("SwiftUI の中身の安全領域 (Loading)", .serialized)
@MainActor
struct LoadingSwiftUISafeAreaTests {
    @Test("[PB-IS-05] 窓全体基準で端に付けた Loading の中身は、重なりを受け取る")
    func PB_IS_05_loadingTopEdgeReceivesOverlap() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await SwiftUIContainerStage.loading(
            content: SafeAreaProbeSwiftUIContent(model: SwiftUISafeAreaProbeModel(), record: record),
            showPlacement: DialogPlacement(verticalAlignment: .start),
            screen: DialogLayoutCase.Size(w: 393, h: 852),
            insets: DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)
        )
        defer { stage.window.isHidden = true }

        await record.expectLatestInsets(top: 59, bottom: 0, "Loading・上端")
    }
}
#endif
