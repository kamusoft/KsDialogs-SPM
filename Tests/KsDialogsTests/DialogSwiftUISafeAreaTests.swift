#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// Dialog の器に載せた SwiftUI の中身から見える安全領域と、そのときの器の矩形を確かめる。
///
/// 基準領域が窓全体のときだけ、位置が端に固定される軸の重なりを中身が標準の安全領域として受け取る。
/// 中央に固定される軸と、窓全体以外の基準領域では受け取らない。どの場合も器の大きさと位置は
/// 安全領域を受け取らないときと同じである。
@Suite("SwiftUI の中身の安全領域 (Dialog)", .serialized)
@MainActor
struct DialogSwiftUISafeAreaTests {
    private static let portrait = DialogLayoutCase.Size(w: 393, h: 852)
    private static let portraitInsets = DialogLayoutCase.Insets(top: 59, bottom: 34, left: 0, right: 0)
    private static let landscape = DialogLayoutCase.Size(w: 852, h: 393)
    private static let landscapeInsets = DialogLayoutCase.Insets(top: 0, bottom: 21, left: 59, right: 59)

    private static let top = DialogPlacement(verticalAlignment: .start)
    private static let bottom = DialogPlacement(verticalAlignment: .end)

    // MARK: - 端の軸の受け取り

    @Test("[PB-IS-01] 窓全体基準で上端に付けた Dialog の中身は、上の重なりを受け取る")
    func PB_IS_01_topEdgeReceivesTopOverlap() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(record: record, placement: Self.top)
        defer { stage.window.isHidden = true }

        await record.expectLatestInsets(top: 59, "上端")
    }

    @Test("[PB-IS-02] 窓全体基準で下端に付けた Dialog の中身は、下の重なりを受け取る")
    func PB_IS_02_bottomEdgeReceivesBottomOverlap() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(record: record, placement: Self.bottom)
        defer { stage.window.isHidden = true }

        await record.expectLatestInsets(bottom: 34, "下端")
    }

    @Test("[PB-IS-03] 窓全体基準で全面に広げた Dialog の中身は、両辺の重なりを受け取る")
    func PB_IS_03_fillReceivesBothOverlaps() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(
            record: record,
            placement: DialogPlacement(horizontalAlignment: .fill, verticalAlignment: .fill)
        )
        defer { stage.window.isHidden = true }

        await record.expectLatestInsets(top: 59, bottom: 34, "全面")
    }

    @Test("[PB-IS-07] 窓が変わると、受け取る安全領域も新しい重なりになる")
    func PB_IS_07_windowChangeUpdatesOverlap() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(
            record: record,
            placement: DialogPlacement(horizontalAlignment: .end, verticalAlignment: .start)
        )
        defer { stage.window.isHidden = true }
        let window = try #require(stage.window as? DialogLayoutTestWindow)

        await record.expectLatestInsets(top: 59, trailing: 0, "縦長の窓")

        window.changeGeometry(screen: Self.landscape, insets: Self.landscapeInsets)

        await record.expectLatestInsets(top: 0, trailing: 59, "横長に変えた後")
    }

    @Test("[PB-IS-08] キーボードの領域は届けない")
    func PB_IS_08_keyboardRegionIsNotDelivered() throws {
        let content = DialogSwiftUIHost.makeContent(FixedSizeSwiftUIContent(contentSize: CGSize(width: 200, height: 100)))
        let host = try #require(
            content.host as? UIHostingController<DialogSwiftUIRoot<FixedSizeSwiftUIContent>>,
            "ホストが SwiftUI のホストであること"
        )

        #expect(host.safeAreaRegions == .container, "システムの領域だけを渡す")
        #expect(!host.safeAreaRegions.contains(.keyboard), "キーボードの領域を渡さない")
    }

    @Test("[PB-IS-09] 比率サイズを伴う全面の軸は中央の軸として扱う")
    func PB_IS_09_proportionalFillIsCenterAxis() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(
            record: record,
            placement: DialogPlacement(verticalAlignment: .fill),
            options: DialogOptions(layoutArea: .window, proportionalHeight: 0.99)
        )
        defer { stage.window.isHidden = true }

        DialogRectExpectation.expect(
            stage.container.contentView.frame,
            equals: CGRect(x: 96.5, y: (852 - 852 * 0.99) / 2, width: 200, height: 852 * 0.99),
            "上下とも安全領域に重なる前提"
        )
        await record.expectNoInsetsEver("比率サイズの全面")
    }

    // MARK: - 中央の軸

    @Test("[PB-IS-04] 中央に置いた Dialog の中身は、重なりがあっても安全領域を受け取らない")
    func PB_IS_04_centerReceivesNoOverlap() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(record: record, model: SwiftUISafeAreaProbeModel(idealHeight: 800))
        defer { stage.window.isHidden = true }

        await record.expectNoInsetsEver("中央・高さ 800")
    }

    // MARK: - 器の大きさと位置

    @Test(
        "[PB-IS-10] 端に付けた中身の器は、要求サイズのまま",
        arguments: [
            (isTop: true, container: CGRect(x: 96.5, y: 0, width: 200, height: 100), content: CGRect(x: 96.5, y: 59, width: 200, height: 41)),
            (isTop: false, container: CGRect(x: 96.5, y: 752, width: 200, height: 100), content: CGRect(x: 96.5, y: 752, width: 200, height: 66))
        ]
    )
    func PB_IS_10_edgeContainerKeepsRequestedSize(isTop: Bool, container: CGRect, content: CGRect) async throws {
        let edge = isTop ? "上端" : "下端"
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(record: record, placement: isTop ? Self.top : Self.bottom)
        defer { stage.window.isHidden = true }

        let frames = await Self.sampleContainerFrames(stage)
        for frame in frames {
            DialogRectExpectation.expect(frame, equals: container, "\(edge)の器")
        }
        let settled = await DialogTestWaiting.waitUntil(timeout: .seconds(2)) {
            record.latestFrame.map { Self.isClose($0, content) } ?? false
        }
        #expect(settled, "\(edge)の中身は器の内側の安全領域に収まる — 期待 \(content) 実測 \(String(describing: record.latestFrame))")
    }

    @Test(
        "[PB-IS-11] 安全領域を無視する中身は、今と同じ位置と大きさ",
        arguments: [
            (isTop: true, expected: CGRect(x: 96.5, y: 0, width: 200, height: 100)),
            (isTop: false, expected: CGRect(x: 96.5, y: 752, width: 200, height: 100))
        ]
    )
    func PB_IS_11_ignoringContentKeepsFrame(isTop: Bool, expected: CGRect) async throws {
        let edge = isTop ? "上端" : "下端"
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(
            record: record,
            placement: isTop ? Self.top : Self.bottom,
            ignoresSafeArea: true
        )
        defer { stage.window.isHidden = true }

        DialogRectExpectation.expect(stage.container.contentView.frame, equals: expected, "\(edge)の器")
        let settled = await DialogTestWaiting.waitUntil(timeout: .seconds(2)) {
            record.latestFrame.map { Self.isClose($0, expected) } ?? false
        }
        #expect(settled, "\(edge)の中身は器の矩形いっぱい — 期待 \(expected) 実測 \(String(describing: record.latestFrame))")
    }

    @Test(
        "[PB-IS-12] 安全領域に収まらない固定サイズの中身でも、器の矩形は変わらない",
        arguments: [
            (isTop: true, ignores: false),
            (isTop: true, ignores: true),
            (isTop: false, ignores: false),
            (isTop: false, ignores: true)
        ]
    )
    func PB_IS_12_fixedSizeContentKeepsContainer(isTop: Bool, ignores: Bool) async throws {
        let note = "\(isTop ? "上端" : "下端")・\(ignores ? "無視あり" : "無視なし")"
        let expected = CGRect(x: 96.5, y: isTop ? 0 : 752, width: 200, height: 100)
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(
            record: record,
            placement: isTop ? Self.top : Self.bottom,
            isFixedSize: true,
            ignoresSafeArea: ignores
        )
        defer { stage.window.isHidden = true }

        for frame in await Self.sampleContainerFrames(stage) {
            DialogRectExpectation.expect(frame, equals: expected, note)
        }
    }

    @Test("[PB-IS-13] 中央に置いた中身は膨らまない")
    func PB_IS_13_centerContentDoesNotGrow() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(record: record, model: SwiftUISafeAreaProbeModel(idealHeight: 800))
        defer { stage.window.isHidden = true }

        for frame in await Self.sampleContainerFrames(stage) {
            DialogRectExpectation.expect(frame, equals: CGRect(x: 96.5, y: 26, width: 200, height: 800), "中央・高さ 800")
        }
    }

    @Test("[PB-IS-14] 中身の要求サイズが変わると、器が追従する")
    func PB_IS_14_containerFollowsContentSizeChange() async throws {
        let record = SwiftUISafeAreaRecord()
        let model = SwiftUISafeAreaProbeModel()
        let stage = try await Self.show(record: record, model: model, placement: Self.top)
        defer { stage.window.isHidden = true }
        await record.expectLatestInsets(top: 59, "変える前")

        model.idealHeight = 160

        let followed = await DialogTestWaiting.waitUntil(timeout: .seconds(2)) {
            stage.window.layoutIfNeeded()
            return abs(stage.container.contentView.frame.height - 160) <= 0.5
        }
        #expect(followed, "器の高さが 160 になる — 実測 \(stage.container.contentView.frame)")
        DialogRectExpectation.expect(
            stage.container.contentView.frame,
            equals: CGRect(x: 96.5, y: 0, width: 200, height: 160),
            "変えた後の器"
        )
        await record.expectLatestInsets(top: 59, "変えた後")
    }

    @Test("[PB-IS-15] 横の安全領域で折り返す本文でも、器の矩形は落ち着く")
    func PB_IS_15_wrappingTextSettles() async throws {
        // 比べる基準: 同じ本文を、一番外側で安全領域を無視して (安全領域を受け取らずに) 出した器の矩形。
        let referenceStage = try await Self.showWrappingText(record: SwiftUISafeAreaRecord(), ignoresSafeArea: true)
        let reference = await Self.sampleContainerFrames(referenceStage)
        referenceStage.window.isHidden = true
        let expected = try #require(reference.last)

        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.showWrappingText(record: record, ignoresSafeArea: false)
        defer { stage.window.isHidden = true }

        let frames = await Self.sampleContainerFrames(stage)
        #expect(frames.allSatisfy { Self.isClose($0, expected) }, "1 秒間、安全領域を受け取らないときと同じ矩形 \(expected) — 実測 \(frames)")
        #expect(expected.width <= 852 + 0.5, "幅は窓の幅を超えない — 基準 \(expected)")
        await record.expectLatestInsets(leading: 59, trailing: 0, "左端")
    }

    @Test("[PB-IS-16] UIView の中身は、今と同じく重なりを safe area として受け取る")
    func PB_IS_16_uiViewContentKeepsUIKitPropagation() {
        let contentView = FixedContentSizeView(contentSize: CGSize(width: 200, height: 100))
        contentView.ksDialogOptions = DialogOptions(layoutArea: .window)
        let stage = DialogLayoutMeasurement.layoutInWindow(
            contentView: contentView,
            showPlacement: Self.top,
            screen: Self.portrait,
            insets: Self.portraitInsets
        )
        defer { stage.window.isHidden = true }

        #expect(abs(contentView.safeAreaInsets.top - 59) <= 0.5, "上 59 — 実測 \(contentView.safeAreaInsets)")
        #expect(abs(contentView.safeAreaInsets.bottom) <= 0.5, "下 0 — 実測 \(contentView.safeAreaInsets)")
        #expect(abs(contentView.frame.height - 100) <= 0.5, "器の高さは 100 — 実測 \(contentView.frame)")
    }

    // MARK: - 窓全体以外の基準領域

    @Test(
        "[PB-IS-17] 既定の基準領域で端に付けた Dialog の中身は、安全領域を受け取らない",
        arguments: [
            (isTop: true, expected: CGRect(x: 96.5, y: 59, width: 200, height: 100)),
            (isTop: false, expected: CGRect(x: 96.5, y: 718, width: 200, height: 100))
        ]
    )
    func PB_IS_17_visibleAreaEdgeReceivesNothing(isTop: Bool, expected: CGRect) async throws {
        let edge = isTop ? "上端" : "下端"
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(
            record: record,
            placement: isTop ? Self.top : Self.bottom,
            options: DialogOptions()
        )
        defer { stage.window.isHidden = true }

        DialogRectExpectation.expect(stage.container.contentView.frame, equals: expected, "\(edge)の器")
        await record.expectNoInsetsEver("可視領域・\(edge)")
    }

    @Test("[PB-IS-18] 既定の基準領域で移動量によりシステムの領域に重なっても、安全領域を受け取らない")
    func PB_IS_18_visibleAreaOffsetOverlapReceivesNothing() async throws {
        let record = SwiftUISafeAreaRecord()
        let stage = try await Self.show(
            record: record,
            placement: DialogPlacement(verticalAlignment: .start, offsetY: -30),
            options: DialogOptions()
        )
        defer { stage.window.isHidden = true }

        DialogRectExpectation.expect(
            stage.container.contentView.frame,
            equals: CGRect(x: 96.5, y: 29, width: 200, height: 100),
            "上に 30 重なる器"
        )
        await record.expectNoInsetsEver("可視領域・移動量 -30")
    }

    // MARK: - 補助

    /// 縦長の窓に、安全領域を記録する SwiftUI の中身の Dialog を出して実効値の固定まで進める。
    private static func show(
        record: SwiftUISafeAreaRecord,
        model: SwiftUISafeAreaProbeModel = SwiftUISafeAreaProbeModel(),
        placement: DialogPlacement? = nil,
        isFixedSize: Bool = false,
        ignoresSafeArea: Bool = false,
        options: DialogOptions = DialogOptions(layoutArea: .window)
    ) async throws -> (container: DialogContainerViewController, window: UIWindow) {
        try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeSwiftUIContent(
                model: model,
                record: record,
                isFixedSize: isFixedSize,
                ignoresSafeArea: ignoresSafeArea,
                options: options
            ),
            showPlacement: placement,
            screen: portrait,
            insets: portraitInsets
        )
    }

    /// 横長の窓に、折り返す長い本文の Dialog を左端に付けて出す。
    private static func showWrappingText(
        record: SwiftUISafeAreaRecord,
        ignoresSafeArea: Bool
    ) async throws -> (container: DialogContainerViewController, window: UIWindow) {
        try await DialogSwiftUIMeasurement.layoutInWindow(
            content: SafeAreaProbeWrappingText(record: record, ignoresSafeArea: ignoresSafeArea),
            showPlacement: DialogPlacement(horizontalAlignment: .start),
            screen: landscape,
            insets: landscapeInsets
        )
    }

    /// 実効値の固定直後から 1 秒間、50 ms ごとに器の中身の矩形を測る。
    private static func sampleContainerFrames(
        _ stage: (container: DialogContainerViewController, window: UIWindow)
    ) async -> [CGRect] {
        var frames = [stage.container.contentView.frame]
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            stage.window.layoutIfNeeded()
            frames.append(stage.container.contentView.frame)
        }
        return frames
    }

    private static func isClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 0.5 && abs(lhs.minY - rhs.minY) <= 0.5
            && abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
    }
}
#endif
