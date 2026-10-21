#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// Toast の器に載せた SwiftUI の中身も、Dialog と同じホストを通って安全領域を受け取ることを確かめる。
///
/// 器を表示 API を通さずに直接重ねるので、表示の期限は進まない。
@Suite("SwiftUI の中身の安全領域 (Toast)", .serialized)
@MainActor
struct ToastSwiftUISafeAreaTests {
    private static let portrait = DialogLayoutCase.Size(w: 393, h: 852)
    private static let portraitInsets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)

    @Test("[PB-IS-06] 窓全体基準で端に付けた Toast の中身は、重なりを受け取る")
    func PB_IS_06_toastBottomEdgeReceivesOverlap() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await SwiftUIContainerStage.toast(
            content: SafeAreaProbeSwiftUIContent(model: SwiftUISafeAreaProbeModel(), record: record),
            showPlacement: DialogPlacement(verticalAlignment: .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        await record.expectLatestInsets(top: 0, bottom: 34, "Toast・下端")
    }

    @Test("[PB-IS-19] 既定の基準領域の Toast の中身は、安全領域を受け取らない")
    func PB_IS_19_defaultToastReceivesNothing() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await SwiftUIContainerStage.toast(
            content: SafeAreaProbeSwiftUIContent(model: SwiftUISafeAreaProbeModel(), record: record, options: nil),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        await record.expectNoInsetsEver("Toast・レイアウトの指定なし")
    }

    @Test("[PB-IS-26] 窓全体基準で下端に付けた縮まない Toast の中身は、器いっぱいに置かれる")
    func PB_IS_26_toastBottomRigidContentFillsContainer() async throws {
        let band = SwiftUIDrawnFrameProbe()
        let background = SwiftUIDrawnFrameProbe()
        let stage = try await SwiftUIContainerStage.toast(
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
        SwiftUIPlacementSampling.expectContainer(samples, equals: container, "Toastの器")
        SwiftUIPlacementSampling.expectDrawn(samples, at: 0, equals: container, "Toastの帯")
        SwiftUIPlacementSampling.expectDrawn(samples, at: 1, equals: container, "Toastの地色")
    }
}
#endif
