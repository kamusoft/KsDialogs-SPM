#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// 表示中に SwiftUI の中身が求める大きさが変わったとき、器がその新しい大きさに追従することを確かめる。
///
/// 理想の幅が広がる・狭まる変化と、文言が長くなる変化の両方を、既定の可視領域と、
/// 窓全体を基準に上端へ付けた形 (中身が安全領域を受け取る形) で見る。
@Suite("SwiftUI の中身の要求サイズの追従", .serialized)
@MainActor
struct DialogSwiftUIContentSizeFollowTests {
    private static let screen = DialogLayoutCase.Size(w: 393, h: 852)
    private static let insets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)

    /// 比べる条件。既定の可視領域 (添付も配置の指定もなし) と、窓全体を基準にした上端。
    enum Condition: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case defaultVisibleArea = "既定の可視領域"
        case windowTopEdge = "窓全体・上端"

        var testDescription: String { rawValue }

        var options: DialogOptions? {
            switch self {
            case .defaultVisibleArea: nil
            case .windowTopEdge: DialogOptions(layoutArea: .window)
            }
        }

        var placement: DialogPlacement? {
            switch self {
            case .defaultVisibleArea: nil
            case .windowTopEdge: DialogPlacement(verticalAlignment: .start)
            }
        }
    }

    @Test("表示中に理想の幅を広げても狭めても、器の幅が追従する", arguments: Condition.allCases)
    func containerFollowsIdealWidth(condition: Condition) async throws {
        let model = MutableSwiftUIContentModel(idealWidth: 200)
        let stage = try await Self.show(
            MutableSwiftUIContent(model: model, kind: .idealWidth, options: condition.options),
            condition: condition
        )
        defer { stage.window.isHidden = true }
        #expect(abs(stage.container.contentView.frame.width - 200) <= 0.5, "最初の幅 — 実測 \(stage.container.contentView.frame)")

        for width in [CGFloat(280), 120] {
            model.idealWidth = width
            let followed = await Self.waitUntilSize(of: stage) { abs($0.width - width) <= 0.5 }
            #expect(followed, "理想の幅を \(width) にした後 — 実測 \(stage.container.contentView.frame)")
            #expect(abs(stage.container.contentView.frame.height - 100) <= 0.5, "高さは変わらない — 実測 \(stage.container.contentView.frame)")
        }
    }

    @Test("表示中に文言を長くすると、器は最初から長い文言で出したときと同じ大きさになる", arguments: Condition.allCases)
    func containerFollowsLongerText(condition: Condition) async throws {
        let longText = "This is a much longer message"
        let expectedStage = try await Self.show(
            MutableSwiftUIContent(model: MutableSwiftUIContentModel(text: longText), kind: .text, options: condition.options),
            condition: condition
        )
        let expected = expectedStage.container.contentView.frame.size
        expectedStage.window.isHidden = true

        let model = MutableSwiftUIContentModel(text: "OK")
        let stage = try await Self.show(
            MutableSwiftUIContent(model: model, kind: .text, options: condition.options),
            condition: condition
        )
        defer { stage.window.isHidden = true }
        #expect(stage.container.contentView.frame.width < expected.width, "短い文言の器は長い文言の器より狭い — 実測 \(stage.container.contentView.frame)")

        model.text = longText

        let followed = await Self.waitUntilSize(of: stage) {
            abs($0.width - expected.width) <= 0.5 && abs($0.height - expected.height) <= 0.5
        }
        #expect(followed, "期待 \(expected) 実測 \(stage.container.contentView.frame)")
    }

    private static func show<Content: View>(
        _ content: Content,
        condition: Condition
    ) async throws -> (container: DialogContainerViewController, window: UIWindow) {
        try await DialogSwiftUIMeasurement.layoutInWindow(
            content: content,
            showPlacement: condition.placement,
            screen: screen,
            insets: insets
        )
    }

    /// 器の中身の大きさが条件を満たすまで、レイアウトを進めながら待つ。
    private static func waitUntilSize(
        of stage: (container: DialogContainerViewController, window: UIWindow),
        _ condition: @MainActor (CGSize) -> Bool
    ) async -> Bool {
        await DialogTestWaiting.waitUntil(timeout: .seconds(2)) {
            stage.window.layoutIfNeeded()
            return condition(stage.container.contentView.frame.size)
        }
    }
}
#endif
