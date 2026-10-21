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

    @Test("[PB-IS-26] 窓全体基準で下端に付けた縮まない Loading の中身は、器いっぱいに置かれる")
    func PB_IS_26_loadingBottomRigidContentFillsContainer() async throws {
        let band = SwiftUIDrawnFrameProbe()
        let background = SwiftUIDrawnFrameProbe()
        let stage = try await SwiftUIContainerStage.loading(
            content: EdgeConfirmSwiftUIContent(handling: .respects, band: band, background: background),
            showPlacement: DialogPlacement(horizontalAlignment: .fill, verticalAlignment: .end),
            screen: DialogLayoutCase.Size(w: 393, h: 852),
            insets: DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)
        )
        defer { stage.window.isHidden = true }

        let samples = await SwiftUIPlacementSampling.sample(
            window: stage.window,
            container: { stage.container.contentView },
            drawn: [band, background]
        )
        let container = try #require(samples.first?.container)
        #expect(abs(container.maxY - 852) <= 0.5, "器の下端は窓の下端 852 — 実測 \(container)")
        SwiftUIPlacementSampling.expectContainer(samples, equals: container, "Loadingの器")
        SwiftUIPlacementSampling.expectDrawn(samples, at: 0, equals: container, "Loadingの帯")
        SwiftUIPlacementSampling.expectDrawn(samples, at: 1, equals: container, "Loadingの地色")
    }
}
#endif
