#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// 大きさを中身に委ねた幅が、有効領域の上限が広がったときに新しい上限まで広がることを確かめる。
///
/// 縦長から横長に変えると、既定の可視領域の幅は 393 から 734 (左右の安全領域 59 を除く) に広がる。
/// 同じ寸法の窓で置き直されたときは求め直さず、器の矩形は変わらない。
@Suite("中身に委ねた幅の上限への追従", .serialized)
@MainActor
struct ContentWidthLimitFollowTests {
    private static let portrait = DialogLayoutCase.Size(w: 393, h: 852)
    private static let portraitInsets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)
    private static let landscape = DialogLayoutCase.Size(w: 852, h: 393)
    private static let landscapeInsets = DialogLayoutCase.Insets(top: 0, bottom: 21, left: 59, right: 59)

    /// 横長の可視領域の幅。
    private static let landscapeVisibleWidth: CGFloat = 734

    /// 1 行に並べると横長の窓の幅を超える長さの本文。
    private static let longText = String(repeating: "Wrap this long body text. ", count: 12)

    /// 折り返す本文の幅の許容誤差 (折り返した行の幅と提案した幅の差を吸収する)。
    private static let wrappedWidthTolerance: CGFloat = 1.0

    @Test("[PB-IS-28] 窓より広い理想の幅を持つ中身は、縦長から横長に変えると広がる")
    func PB_IS_28_wideIdealWidthWidensOnRotation() async throws {
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: MutableSwiftUIContent(model: MutableSwiftUIContentModel(idealWidth: 600), kind: .idealWidth),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        let window = try #require(stage.window as? DialogLayoutTestWindow)
        let container = stage.container.contentView
        #expect(abs(container.frame.width - 393) <= 0.5, "縦長では 393 で頭打ち — 実測 \(container.frame)")

        window.changeGeometry(screen: Self.landscape, insets: Self.landscapeInsets)
        let widened = await Self.waitUntilWidth(window, container) { abs($0 - 600) <= 0.5 }
        #expect(widened, "横長に変えた後の幅は 600 — 実測 \(container.frame)")
        await Self.expectSteadyWidth(window, container, 600, tolerance: 0.5, "横長に変えた後")

        window.changeGeometry(screen: Self.portrait, insets: Self.portraitInsets)
        let narrowed = await Self.waitUntilWidth(window, container) { abs($0 - 393) <= 0.5 }
        #expect(narrowed, "縦長に戻した後の幅は 393 — 実測 \(container.frame)")
        await Self.expectSteadyWidth(window, container, 393, tolerance: 0.5, "縦長に戻した後")
    }

    @Test("[PB-IS-29] 中央に置いた長い本文は、縦長から横長に変えると有効領域の幅まで広がる")
    func PB_IS_29_centeredLongTextWidensOnRotation() async throws {
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: MutableSwiftUIContent(model: MutableSwiftUIContentModel(text: Self.longText), kind: .text),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        let window = try #require(stage.window as? DialogLayoutTestWindow)
        let container = stage.container.contentView

        window.changeGeometry(screen: Self.landscape, insets: Self.landscapeInsets)
        let widened = await Self.waitUntilWidth(window, container) {
            abs($0 - Self.landscapeVisibleWidth) <= Self.wrappedWidthTolerance
        }
        #expect(widened, "横長の有効領域の幅 734 — 実測 \(container.frame)")
        await Self.expectSteadyWidth(window, container, Self.landscapeVisibleWidth, tolerance: Self.wrappedWidthTolerance, "横長に変えた後")
    }

    @Test("[PB-IS-34] 有効領域で頭打ちになった本文は、同じ寸法の窓で置き直されても幅が変わらない")
    func PB_IS_34_cappedTextKeepsFrameOnSameSizeRelayout() async throws {
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: MutableSwiftUIContent(model: MutableSwiftUIContentModel(text: Self.longText), kind: .text),
            screen: Self.landscape,
            insets: Self.landscapeInsets
        )
        defer { stage.window.isHidden = true }
        let window = try #require(stage.window as? DialogLayoutTestWindow)
        let container = stage.container.contentView
        let capped = await Self.waitUntilWidth(window, container) {
            abs($0 - Self.landscapeVisibleWidth) <= Self.wrappedWidthTolerance
        }
        #expect(capped, "有効領域の幅 734 で落ち着く — 実測 \(container.frame)")
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(20))
            window.layoutIfNeeded()
        }
        let settled = container.frame

        var frames: [CGRect] = []
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            // 同じ寸法・同じ安全領域のまま、窓の再レイアウトを起こす (器は置き直される)。
            window.changeGeometry(screen: Self.landscape, insets: Self.landscapeInsets)
            frames.append(container.frame)
        }
        #expect(
            frames.allSatisfy { Self.isClose($0, settled) },
            "1 秒間、器の矩形は \(settled) のまま — 実測 \(frames)"
        )
    }

    @Test("[PB-IS-30] UIView の中身も、縦長から横長に変えると広がる")
    func PB_IS_30_uiViewLongTextWidensOnRotation() async throws {
        let contentView = MessageTestContentView(message: Self.longText)
        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        let window = try #require(stage.window as? DialogLayoutTestWindow)
        let container = stage.container.contentView
        #expect(container.frame.width <= 393 + 0.5, "縦長では 393 で頭打ち — 実測 \(container.frame)")

        window.changeGeometry(screen: Self.landscape, insets: Self.landscapeInsets)
        let widened = await Self.waitUntilWidth(window, container) {
            abs($0 - Self.landscapeVisibleWidth) <= Self.wrappedWidthTolerance
        }
        #expect(widened, "横長の有効領域の幅 734 — 実測 \(container.frame)")
        await Self.expectSteadyWidth(window, container, Self.landscapeVisibleWidth, tolerance: Self.wrappedWidthTolerance, "横長に変えた後")
    }

    @Test("[PB-IS-31] Loading・Toast の中身も、縦長から横長に変えると広がる", arguments: ["Loading", "Toast"])
    func PB_IS_31_loadingAndToastWidenOnRotation(kind: String) async throws {
        let content = MutableSwiftUIContent(model: MutableSwiftUIContentModel(text: Self.longText), kind: .text)
        let window: DialogLayoutTestWindow
        let container: UIView
        if kind == "Loading" {
            let stage = try await SwiftUIContainerStage.loading(content: content, screen: Self.portrait, insets: Self.portraitInsets)
            window = stage.window
            container = stage.container.contentView
        } else {
            let stage = try await SwiftUIContainerStage.toast(content: content, screen: Self.portrait, insets: Self.portraitInsets)
            window = stage.window
            container = stage.container.contentView
        }
        defer { window.isHidden = true }
        #expect(container.frame.width <= 393 + 0.5, "\(kind) — 縦長では 393 で頭打ち。実測 \(container.frame)")

        window.changeGeometry(screen: Self.landscape, insets: Self.landscapeInsets)
        let widened = await Self.waitUntilWidth(window, container) {
            abs($0 - Self.landscapeVisibleWidth) <= Self.wrappedWidthTolerance
        }
        #expect(widened, "\(kind) — 横長の有効領域の幅 734。実測 \(container.frame)")
    }

    // MARK: - 補助

    private static func waitUntilWidth(
        _ window: UIWindow,
        _ container: UIView,
        _ condition: @MainActor (CGFloat) -> Bool
    ) async -> Bool {
        await DialogTestWaiting.waitUntil(timeout: .seconds(2)) {
            window.layoutIfNeeded()
            return condition(container.frame.width)
        }
    }

    /// 今から 1 秒間、器の幅が `width` のまま変わらないことを確かめる。
    private static func expectSteadyWidth(
        _ window: UIWindow,
        _ container: UIView,
        _ width: CGFloat,
        tolerance: CGFloat,
        _ note: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        var frames: [CGRect] = []
        for _ in 0...20 {
            window.layoutIfNeeded()
            frames.append(container.frame)
            try? await Task.sleep(for: .milliseconds(50))
        }
        let first = frames[0]
        #expect(
            frames.allSatisfy { abs($0.width - width) <= tolerance && isClose($0, first) },
            "\(note) — 1 秒間、幅 \(width) のまま変わらない。実測 \(frames)",
            sourceLocation: sourceLocation
        )
    }

    private static func isClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 0.5 && abs(lhs.minY - rhs.minY) <= 0.5
            && abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
    }
}
#endif
