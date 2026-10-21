#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// 窓全体を基準に片側の端へ付けた SwiftUI の中身が安全領域の内側に収まらないとき、
/// 内側の辺にそろって器いっぱいに置かれることを確かめる (Dialog)。
///
/// 中身の位置は、中身に重ねた UIView の目印で描かれた位置を測る。中身から読む geometry は
/// 描画と食い違うことがあるため、位置の判定には使わない。
@Suite("SwiftUI の中身の内側の辺へのそろえ (Dialog)", .serialized)
@MainActor
struct DialogSwiftUIInnerEdgeAlignmentTests {
    private static let portrait = DialogLayoutCase.Size(w: 393, h: 852)
    private static let portraitInsets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)
    private static let landscape = DialogLayoutCase.Size(w: 852, h: 393)
    private static let landscapeInsets = DialogLayoutCase.Insets(top: 0, bottom: 21, left: 59, right: 59)

    private static let window = DialogOptions(layoutArea: .window)

    // MARK: - 縮まない中身

    @Test("[PB-IS-20] 下端に付けた縮まない中身は、器いっぱいに置かれる", arguments: EdgeConfirmSwiftUIContent.SafeAreaHandling.allCases)
    func PB_IS_20_bottomRigidContentFillsContainer(handling: EdgeConfirmSwiftUIContent.SafeAreaHandling) async throws {
        let band = SwiftUIDrawnFrameProbe()
        let background = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: EdgeConfirmSwiftUIContent(handling: handling, band: band, background: background),
            showPlacement: DialogPlacement(horizontalAlignment: .fill, verticalAlignment: .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        let samples = await Self.sample(stage, drawn: [band, background])
        let container = try #require(samples.first?.container)
        #expect(abs(container.maxY - 852) <= 0.5, "器の下端は窓の下端 852 — 実測 \(container)")
        #expect(container.height > Self.portraitInsets.bottom, "帯は下の重なりより高い — 実測 \(container)")
        SwiftUIPlacementSampling.expectContainer(samples, equals: container, "\(handling.rawValue)の器")
        SwiftUIPlacementSampling.expectDrawn(samples, at: 0, equals: container, "\(handling.rawValue)の帯")
        SwiftUIPlacementSampling.expectDrawn(samples, at: 1, equals: container, "\(handling.rawValue)の地色")
    }

    @Test(
        "[PB-IS-21] 上端に付けた縮まない中身は、器いっぱいに置かれる",
        arguments: [EdgeConfirmSwiftUIContent.SafeAreaHandling.respects, .ignoresOutermost]
    )
    func PB_IS_21_topRigidContentFillsContainer(handling: EdgeConfirmSwiftUIContent.SafeAreaHandling) async throws {
        let band = SwiftUIDrawnFrameProbe()
        let background = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: EdgeConfirmSwiftUIContent(handling: handling, band: band, background: background),
            showPlacement: DialogPlacement(horizontalAlignment: .fill, verticalAlignment: .start),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        let samples = await Self.sample(stage, drawn: [band, background])
        let container = try #require(samples.first?.container)
        #expect(abs(container.minY) <= 0.5, "器は y 0 から始まる — 実測 \(container)")
        SwiftUIPlacementSampling.expectContainer(samples, equals: container, "\(handling.rawValue)の器")
        SwiftUIPlacementSampling.expectDrawn(samples, at: 0, equals: container, "\(handling.rawValue)の帯")
        SwiftUIPlacementSampling.expectDrawn(samples, at: 1, equals: container, "\(handling.rawValue)の地色")
    }

    @Test(
        "[PB-IS-22] 左右の端に付けた縮まない中身は、書字方向によらず器いっぱいに置かれる",
        arguments: [
            (isRightEdge: true, isRightToLeft: false, switchesAfterShow: false),
            (isRightEdge: true, isRightToLeft: true, switchesAfterShow: false),
            (isRightEdge: true, isRightToLeft: true, switchesAfterShow: true),
            (isRightEdge: false, isRightToLeft: false, switchesAfterShow: false),
            (isRightEdge: false, isRightToLeft: true, switchesAfterShow: false),
            (isRightEdge: false, isRightToLeft: true, switchesAfterShow: true)
        ]
    )
    func PB_IS_22_sideRigidContentFillsContainerRegardlessOfDirection(
        isRightEdge: Bool,
        isRightToLeft: Bool,
        switchesAfterShow: Bool
    ) async throws {
        let direction = isRightToLeft ? (switchesAfterShow ? "表示後に右から左へ切り替え" : "最初から右から左") : "左から右"
        let note = "\(isRightEdge ? "右端" : "左端")・\(direction)"
        let expected = CGRect(x: isRightEdge ? 652 : 0, y: 146.5, width: 200, height: 100)
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(
                model: SwiftUISafeAreaProbeModel(isFixedSize: true),
                record: SwiftUISafeAreaRecord(),
                drawn: drawn
            ),
            showPlacement: DialogPlacement(horizontalAlignment: isRightEdge ? .end : .start),
            screen: Self.landscape,
            insets: Self.landscapeInsets,
            layoutDirection: isRightToLeft && !switchesAfterShow ? .rightToLeft : nil
        )
        defer { stage.window.isHidden = true }
        if isRightToLeft, switchesAfterShow {
            stage.window.traitOverrides.layoutDirection = .rightToLeft
            stage.window.layoutIfNeeded()
        }
        let hostedView = try #require(stage.container.contentView.subviews.first)
        #expect(
            hostedView.traitCollection.layoutDirection == (isRightToLeft ? .rightToLeft : .leftToRight),
            "\(note) — ホストの書字方向 \(hostedView.traitCollection.layoutDirection.rawValue)"
        )

        let settled = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, expected)
        }
        #expect(settled, "\(note) — 期待 \(expected) 実測 \(String(describing: drawn.windowFrame))")
        let samples = await Self.sample(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(samples, equals: expected, "\(note)の器")
        SwiftUIPlacementSampling.expectDrawn(samples, equals: expected, "\(note)の中身")
    }

    @Test(
        "[PB-IS-35] 器より大きい縮まない中身は、内側の辺にそろって付いた側へはみ出す",
        arguments: [
            (isTop: false, drawn: CGRect(x: 96.5, y: 0, width: 200, height: 1000)),
            (isTop: true, drawn: CGRect(x: 96.5, y: -148, width: 200, height: 1000))
        ]
    )
    func PB_IS_35_oversizedRigidContentOverflowsTowardAnchoredEdge(isTop: Bool, drawn expected: CGRect) async throws {
        let edge = isTop ? "上端" : "下端"
        let record = SwiftUISafeAreaRecord()
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(
                model: SwiftUISafeAreaProbeModel(idealHeight: 1000, isFixedSize: true),
                record: record,
                drawn: drawn
            ),
            showPlacement: DialogPlacement(verticalAlignment: isTop ? .start : .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        let settled = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, expected)
        }
        #expect(settled, "\(edge) — 期待 \(expected) 実測 \(String(describing: drawn.windowFrame))")
        let samples = await Self.sample(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(samples, equals: CGRect(x: 96.5, y: 0, width: 200, height: 852), "\(edge)の器")
        SwiftUIPlacementSampling.expectDrawn(samples, equals: expected, "\(edge)の中身")
        #expect(
            SwiftUIPlacementSampling.isClose(record.latestFrame, expected),
            "\(edge) — 中身から読める位置も同じ。実測 \(String(describing: record.latestFrame))"
        )
    }

    // MARK: - 一部だけ縮む中身

    @Test(
        "[PB-IS-23] 一部だけ縮む中身は、縮んだうえで内側の辺にそろう",
        arguments: [
            (isTop: true, container: CGRect(x: 96.5, y: 0, width: 200, height: 100), drawn: CGRect(x: 96.5, y: 20, width: 200, height: 80)),
            (isTop: false, container: CGRect(x: 96.5, y: 752, width: 200, height: 100), drawn: CGRect(x: 96.5, y: 752, width: 200, height: 80))
        ]
    )
    func PB_IS_23_partiallyShrinkingContentAlignsToInnerEdge(isTop: Bool, container: CGRect, drawn expected: CGRect) async throws {
        let edge = isTop ? "上端" : "下端"
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(
                model: SwiftUISafeAreaProbeModel(minHeight: 80),
                record: SwiftUISafeAreaRecord(),
                drawn: drawn
            ),
            showPlacement: DialogPlacement(verticalAlignment: isTop ? .start : .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        let settled = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, expected)
        }
        #expect(settled, "\(edge) — 期待 \(expected) 実測 \(String(describing: drawn.windowFrame))")
        let samples = await Self.sample(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(samples, equals: container, "\(edge)の器")
        SwiftUIPlacementSampling.expectDrawn(samples, equals: expected, "\(edge)の中身")
    }

    // MARK: - 中身から読める位置

    @Test(
        "[PB-IS-24] 中身から読める位置は、描かれた位置と一致する",
        arguments: [
            (isTop: true, isFixedSize: false),
            (isTop: false, isFixedSize: false),
            (isTop: true, isFixedSize: true),
            (isTop: false, isFixedSize: true)
        ]
    )
    func PB_IS_24_readableGeometryMatchesDrawnFrame(isTop: Bool, isFixedSize: Bool) async throws {
        let note = "\(isTop ? "上端" : "下端")・\(isFixedSize ? "固定サイズ" : "縮められる中身")"
        let containerY: CGFloat = isTop ? 0 : 752
        let expected: CGRect = switch (isFixedSize, isTop) {
        case (true, _): CGRect(x: 96.5, y: containerY, width: 200, height: 100)
        case (false, true): CGRect(x: 96.5, y: 59, width: 200, height: 41)
        case (false, false): CGRect(x: 96.5, y: 752, width: 200, height: 66)
        }
        let outer = SwiftUISafeAreaRecord()
        let inner = SwiftUISafeAreaRecord()
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(
                model: SwiftUISafeAreaProbeModel(isFixedSize: isFixedSize),
                record: outer,
                innerRecord: inner,
                drawn: drawn
            ),
            showPlacement: DialogPlacement(verticalAlignment: isTop ? .start : .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        // 記録が落ち着くまで待つ: 1 秒間進めたあとの最後の記録を読む。
        let samples = await Self.sample(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectDrawn(samples, equals: expected, "\(note)の描かれた位置")
        #expect(
            SwiftUIPlacementSampling.isClose(outer.latestFrame, expected),
            "\(note) — 一番外側から読む位置。実測 \(String(describing: outer.latestFrame))、履歴 \(outer.frames)"
        )
        #expect(
            SwiftUIPlacementSampling.isClose(inner.latestFrame, expected),
            "\(note) — 内側の子から読む位置。実測 \(String(describing: inner.latestFrame))、履歴 \(inner.frames)"
        )
        let expectedTop: CGFloat = !isFixedSize && isTop ? 59 : 0
        let expectedBottom: CGFloat = !isFixedSize && !isTop ? 34 : 0
        await outer.expectLatestInsets(top: expectedTop, bottom: expectedBottom, "\(note)の一番外側が受け取る安全領域")
    }

    // MARK: - 表示中の切り替わり

    @Test("[PB-IS-25] 中身の大きさが変わって収まらなくなっても、器いっぱいに落ち着く")
    func PB_IS_25_settlesAfterContentSizeChanges() async throws {
        let model = SwiftUISafeAreaProbeModel(isFixedSize: true)
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(model: model, record: SwiftUISafeAreaRecord(), drawn: drawn),
            showPlacement: DialogPlacement(verticalAlignment: .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        let target = CGRect(x: 96.5, y: 692, width: 200, height: 160)

        model.idealHeight = 160
        let grown = await Self.sampleEachPass(stage, drawn: [drawn])
        #expect(
            grown.allSatisfy { abs(($0.drawn[0]?.minY ?? .nan) - $0.container.minY) <= 0.5 },
            "どのパスでも中身の上の辺は器の上の辺にそろったまま (跳ねない) — 実測 \(grown.map { ($0.container.minY, $0.drawn[0]?.minY) })"
        )
        let firstSettled = try #require(
            grown.firstIndex { SwiftUIPlacementSampling.isClose($0.container, target) },
            "器が \(target) にならなかった — 実測 \(grown.map(\.container))"
        )
        let afterGrowth = Array(grown[firstSettled...])
        SwiftUIPlacementSampling.expectContainer(afterGrowth, equals: target, "固定 200 × 160 の器")
        SwiftUIPlacementSampling.expectDrawn(afterGrowth, equals: target, "固定 200 × 160 の中身")

        model.isFixedSize = false
        let shrinkable = await Self.sampleEachPass(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(shrinkable, equals: target, "縮められる中身に変えた後の器")
        let settled = CGRect(x: 96.5, y: 692, width: 200, height: 126)
        let tail = Array(shrinkable.suffix(10))
        SwiftUIPlacementSampling.expectDrawn(tail, equals: settled, "縮められる中身に変えた後の中身")
    }

    @Test("[PB-IS-33] 安全領域だけが変わって収まる / 収まらないが切り替わっても、新しい状態に落ち着く")
    func PB_IS_33_settlesAfterSafeAreaChanges() async throws {
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(
                model: SwiftUISafeAreaProbeModel(minHeight: 80),
                record: SwiftUISafeAreaRecord(),
                drawn: drawn
            ),
            showPlacement: DialogPlacement(verticalAlignment: .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        let window = try #require(stage.window as? DialogLayoutTestWindow)
        let container = CGRect(x: 96.5, y: 752, width: 200, height: 100)
        let shrunk = CGRect(x: 96.5, y: 752, width: 200, height: 80)
        let initial = await SwiftUIPlacementSampling.waitUntilDrawn(window: window, drawn) {
            SwiftUIPlacementSampling.isClose($0, shrunk)
        }
        #expect(initial, "変える前の中身 — 実測 \(String(describing: drawn.windowFrame))")

        let noBottom = DialogLayoutCase.Insets(top: 59, bottom: 0, left: 0, right: 0)
        window.changeGeometry(screen: Self.portrait, insets: noBottom)
        let withoutOverlap = await Self.sampleEachPass(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(withoutOverlap, equals: container, "下の安全領域 0 の器")
        SwiftUIPlacementSampling.expectDrawn(Array(withoutOverlap.suffix(10)), equals: container, "下の安全領域 0 の中身")

        window.changeGeometry(screen: Self.portrait, insets: Self.portraitInsets)
        let withOverlap = await Self.sampleEachPass(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(withOverlap, equals: container, "下の安全領域 34 に戻した器")
        SwiftUIPlacementSampling.expectDrawn(Array(withOverlap.suffix(10)), equals: shrunk, "下の安全領域 34 に戻した中身")
        let passes = withoutOverlap + withOverlap
        #expect(
            passes.allSatisfy { abs(($0.drawn[0]?.minY ?? .nan) - 752) <= 0.5 },
            "どのパスでも中身の上の辺は器の上の辺 752 のまま (跳ねない) — 実測 \(passes.map { $0.drawn[0]?.minY })"
        )
    }

    @Test(
        "縮められる範囲だけが変わって収まらなくなっても、器いっぱいに落ち着く",
        arguments: [
            (isTop: false, before: CGRect(x: 96.5, y: 752, width: 200, height: 66), target: CGRect(x: 96.5, y: 752, width: 200, height: 100)),
            (isTop: true, before: CGRect(x: 96.5, y: 59, width: 200, height: 41), target: CGRect(x: 96.5, y: 0, width: 200, height: 100))
        ]
    )
    func settlesAfterOnlyShrinkableRangeChanges(isTop: Bool, before: CGRect, target: CGRect) async throws {
        let edge = isTop ? "上端" : "下端"
        let model = SwiftUISafeAreaProbeModel()
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(model: model, record: SwiftUISafeAreaRecord(), drawn: drawn),
            showPlacement: DialogPlacement(verticalAlignment: isTop ? .start : .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        let container = CGRect(x: 96.5, y: target.minY, width: 200, height: 100)
        let initial = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, before)
        }
        #expect(initial, "\(edge) — 変える前の中身。期待 \(before) 実測 \(String(describing: drawn.windowFrame))")

        // 理想の大きさ・器・安全領域は変えず、縮められる範囲だけを無くす。
        model.minHeight = 100
        let settled = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, target)
        }
        #expect(settled, "\(edge) — 期待 \(target) 実測 \(String(describing: drawn.windowFrame))")
        let samples = await Self.sampleEachPass(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(samples, equals: container, "\(edge)の器")
        SwiftUIPlacementSampling.expectDrawn(samples, equals: target, "\(edge)の中身")
    }

    @Test(
        "縮められる範囲だけが変わって収まる状態へ戻ると、そろえが外れて安全領域の内側に落ち着く",
        arguments: [
            (isTop: false, aligned: CGRect(x: 96.5, y: 0, width: 200, height: 1000)),
            (isTop: true, aligned: CGRect(x: 96.5, y: -148, width: 200, height: 1000))
        ]
    )
    func settlesBackAfterShrinkableRangeReturns(isTop: Bool, aligned: CGRect) async throws {
        let edge = isTop ? "上端" : "下端"
        let model = SwiftUISafeAreaProbeModel(idealHeight: 1000)
        let outer = SwiftUISafeAreaRecord()
        let inner = SwiftUISafeAreaRecord()
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(model: model, record: outer, innerRecord: inner, drawn: drawn),
            showPlacement: DialogPlacement(verticalAlignment: isTop ? .start : .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        // 器は有効領域 (窓全体) で頭打ちになる。縮められる中身は安全領域の内側に収まる。
        let container = CGRect(x: 96.5, y: 0, width: 200, height: 852)
        let inside = CGRect(x: 96.5, y: 59, width: 200, height: 759)
        let initial = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, inside)
        }
        #expect(initial, "\(edge) — 最初から縮められる中身。期待 \(inside) 実測 \(String(describing: drawn.windowFrame))")

        // 理想の大きさ・器・安全領域は変えず、縮められる範囲だけを無くして収まらなくする。
        model.minHeight = 1000
        let alignedSettled = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, aligned)
        }
        #expect(alignedSettled, "\(edge) — 縮めなくした中身。期待 \(aligned) 実測 \(String(describing: drawn.windowFrame))")

        // 縮められる範囲を戻し、収まる状態へ戻す。
        model.minHeight = nil
        let settled = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, inside)
        }
        #expect(settled, "\(edge) — 縮められる範囲を戻した中身。期待 \(inside) 実測 \(String(describing: drawn.windowFrame))")
        let samples = await Self.sampleEachPass(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(samples, equals: container, "\(edge)の器")
        SwiftUIPlacementSampling.expectDrawn(samples, equals: inside, "\(edge)の中身")
        #expect(
            SwiftUIPlacementSampling.isClose(outer.latestFrame, inside),
            "\(edge) — 一番外側から読む位置。実測 \(String(describing: outer.latestFrame))、履歴 \(outer.frames)"
        )
        #expect(
            SwiftUIPlacementSampling.isClose(inner.latestFrame, inside),
            "\(edge) — 内側の子から読む位置。実測 \(String(describing: inner.latestFrame))、履歴 \(inner.frames)"
        )
        await outer.expectLatestInsets(top: 59, bottom: 34, "\(edge)の一番外側が受け取る安全領域")
    }

    // MARK: - 比率サイズ

    @Test("[PB-IS-32] 比率サイズで下端に付けた縮まない中身も、内側の辺にそろう")
    func PB_IS_32_proportionalBottomRigidContentAlignsToInnerEdge() async throws {
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(
                model: SwiftUISafeAreaProbeModel(idealHeight: 60, isFixedSize: true),
                record: SwiftUISafeAreaRecord(),
                options: DialogOptions(layoutArea: .window, proportionalHeight: 0.1),
                drawn: drawn
            ),
            showPlacement: DialogPlacement(verticalAlignment: .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }
        let expected = CGRect(x: 96.5, y: 766.8, width: 200, height: 60)

        let settled = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, expected)
        }
        #expect(settled, "期待 \(expected) 実測 \(String(describing: drawn.windowFrame))")
        let samples = await Self.sample(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(samples, equals: CGRect(x: 96.5, y: 766.8, width: 200, height: 85.2), "器")
        SwiftUIPlacementSampling.expectDrawn(samples, equals: expected, "中身")
    }

    // MARK: - 並び方を変えない軸

    @Test(
        "[PB-IS-27] 両側の端と中央の軸、既定の基準領域では、並び方を変えない",
        arguments: [
            (isFilled: true, isTop: true, container: CGRect(x: 0, y: 0, width: 393, height: 852), drawn: CGRect(x: 96.5, y: 388.5, width: 200, height: 100)),
            (isFilled: false, isTop: true, container: CGRect(x: 96.5, y: 59, width: 200, height: 100), drawn: CGRect(x: 96.5, y: 59, width: 200, height: 100)),
            (isFilled: false, isTop: false, container: CGRect(x: 96.5, y: 718, width: 200, height: 100), drawn: CGRect(x: 96.5, y: 718, width: 200, height: 100))
        ]
    )
    func PB_IS_27_otherAxesKeepArrangement(isFilled: Bool, isTop: Bool, container: CGRect, drawn expected: CGRect) async throws {
        let note = isFilled ? "窓全体・全面" : "可視領域・\(isTop ? "上端" : "下端")"
        let drawn = SwiftUIDrawnFrameProbe()
        let stage = try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(
                model: SwiftUISafeAreaProbeModel(isFixedSize: true),
                record: SwiftUISafeAreaRecord(),
                options: isFilled ? Self.window : nil,
                drawn: drawn
            ),
            showPlacement: isFilled
                ? DialogPlacement(horizontalAlignment: .fill, verticalAlignment: .fill)
                : DialogPlacement(verticalAlignment: isTop ? .start : .end),
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        let settled = await SwiftUIPlacementSampling.waitUntilDrawn(window: stage.window, drawn) {
            SwiftUIPlacementSampling.isClose($0, expected)
        }
        #expect(settled, "\(note) — 期待 \(expected) 実測 \(String(describing: drawn.windowFrame))")
        let samples = await Self.sample(stage, drawn: [drawn])
        SwiftUIPlacementSampling.expectContainer(samples, equals: container, "\(note)の器")
        SwiftUIPlacementSampling.expectDrawn(samples, equals: expected, "\(note)の中身")
    }

    // MARK: - 補助

    /// 今から 1 秒間、5 ms ごとにレイアウトパスを走らせて、パスごとの矩形を測る。
    private static func sampleEachPass(
        _ stage: (container: DialogContainerViewController, window: UIWindow),
        drawn: [SwiftUIDrawnFrameProbe]
    ) async -> [SwiftUIPlacementSample] {
        await SwiftUIPlacementSampling.sample(
            window: stage.window,
            container: { stage.container.contentView },
            drawn: drawn,
            interval: .milliseconds(5),
            count: 200
        )
    }

    private static func sample(
        _ stage: (container: DialogContainerViewController, window: UIWindow),
        drawn: [SwiftUIDrawnFrameProbe]
    ) async -> [SwiftUIPlacementSample] {
        await SwiftUIPlacementSampling.sample(
            window: stage.window,
            container: { stage.container.contentView },
            drawn: drawn
        )
    }
}
#endif
