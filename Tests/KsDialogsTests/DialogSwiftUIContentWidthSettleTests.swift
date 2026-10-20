#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// 窓より広い理想の幅を持つ SwiftUI の中身の器が、置かれる幅に合わせて落ち着くことを確かめる。
///
/// 折り返す本文は、器が置ける幅で折り返した高さを持つ。中身が安全領域を受け取っても、
/// 表示中に窓が広がっても、同じ条件で最初から出した器と同じ大きさになる。
@Suite("SwiftUI の中身の幅の頭打ちと窓の変化", .serialized)
@MainActor
struct DialogSwiftUIContentWidthSettleTests {
    private static let portrait = DialogLayoutCase.Size(w: 393, h: 852)
    private static let portraitInsets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)
    private static let landscape = DialogLayoutCase.Size(w: 852, h: 393)
    private static let landscapeInsets = DialogLayoutCase.Insets(top: 0, bottom: 21, left: 59, right: 59)

    /// 1 行に並べると窓の幅を超える長さの本文。
    private static let longText = String(repeating: "Wrap this long body text. ", count: 12)

    @Test(
        "縦長の窓で窓全体の端に付けた長い本文の器は、可視領域の上端の器と同じ大きさになる",
        arguments: [DialogAlignment.start, .end]
    )
    func windowEdgeLongTextMatchesVisibleArea(alignment: DialogAlignment) async throws {
        let reference = try await Self.settledSize(
            options: nil,
            placement: DialogPlacement(verticalAlignment: .start),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        let actual = try await Self.settledSize(
            options: DialogOptions(layoutArea: .window),
            placement: DialogPlacement(verticalAlignment: alignment),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )

        #expect(Self.isClose(actual, reference), "期待 \(reference) 実測 \(actual)")
    }

    @Test("可視領域で水平に広げた長い本文の器は、窓を横長に変えると最初から横長で出した器と同じ大きさになる")
    func filledLongTextFollowsWiderWindow() async throws {
        let placement = DialogPlacement(horizontalAlignment: .fill)
        let reference = try await Self.settledSize(
            options: nil,
            placement: placement,
            screen: Self.landscape,
            insets: Self.landscapeInsets
        )

        let stage = try await Self.show(
            MutableSwiftUIContent(model: MutableSwiftUIContentModel(text: Self.longText), kind: .text),
            placement: placement,
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        let window = try #require(stage.window as? DialogLayoutTestWindow)
        window.changeGeometry(screen: Self.landscape, insets: Self.landscapeInsets)

        let followed = await Self.waitUntilSize(of: stage) { Self.isClose($0, reference) }
        #expect(followed, "期待 \(reference) 実測 \(stage.container.contentView.frame)")
    }

    // MARK: - 補助

    /// 長い本文の Dialog を出し、1 秒間レイアウトを進めて落ち着いた器の大きさを返す。
    private static func settledSize(
        options: DialogOptions?,
        placement: DialogPlacement?,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) async throws -> CGSize {
        let stage = try await show(
            MutableSwiftUIContent(model: MutableSwiftUIContentModel(text: longText), kind: .text, options: options),
            placement: placement,
            screen: screen,
            insets: insets
        )
        defer { stage.window.isHidden = true }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            stage.window.layoutIfNeeded()
        }
        return stage.container.contentView.frame.size
    }

    private static func show<Content: View>(
        _ content: Content,
        placement: DialogPlacement?,
        screen: DialogLayoutCase.Size,
        insets: DialogLayoutCase.Insets
    ) async throws -> (container: DialogContainerViewController, window: UIWindow) {
        try await DialogSwiftUIMeasurement.layoutInWindow(
            content: content,
            showPlacement: placement,
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

    private static func isClose(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
    }
}
#endif
