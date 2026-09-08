#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Loading の器メタ属性の適用 (core/ADR-0022) を確かめる。
///
/// レイアウト系の属性は Dialog と同じ意味・同じ供給規則 (core/ADR-0015) で効き、
/// isCanceledOnTouchOutside だけは常に無効になる。
@Suite("Loading の器メタ属性の適用", .serialized)
@MainActor
struct LoadingAttributeTests {
    private static let contentSize = CGSize(width: 120, height: 80)
    /// 中身の外側にあたる点 (中身は既定値では中央に置かれる)。
    private static let outsidePoint = CGPoint(x: 5, y: 5)

    @Test("[LD-AT-01] placement 引数で既定ローディングの配置が変わる")
    func LD_AT_01_placementArgumentMovesDefaultLoading() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        await harness.loading.show()
        let centeredFrame = try #require(harness.contentView).frame
        await harness.loading.hide()

        await harness.loading.show(
            message: nil,
            placement: DialogPlacement(
                horizontalAlignment: .start,
                verticalAlignment: .start,
                offsetX: 10,
                offsetY: 20
            )
        )
        let placedFrame = try #require(harness.contentView).frame
        await harness.loading.hide()

        // 基準は可視領域 (上 59) から余白 24 を控除した有効領域の前端 + オフセット。
        let tolerance = DialogLayoutCaseLoader.table.tolerance
        #expect(abs(Double(placedFrame.minX) - (24 + 10)) <= tolerance, "実測 \(placedFrame)")
        #expect(abs(Double(placedFrame.minY) - (59 + 24 + 20)) <= tolerance, "実測 \(placedFrame)")
        #expect(placedFrame.minX != centeredFrame.minX)
        #expect(placedFrame.minY != centeredFrame.minY)
    }

    @Test("[LD-AT-02] カスタム View の添付属性が Dialog と同じ優先順位で効く")
    func LD_AT_02_attachedPlacementIsReplacedByShowArgument() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            // 添付の実効値: 左上寄せ + 水平方向へ 30 の移動。
            view.ksDialogPlacement = DialogPlacement(
                horizontalAlignment: .start,
                verticalAlignment: .start,
                offsetX: 30
            )
            viewRecorder.record(view)
            return view
        }
        let tolerance = DialogLayoutCaseLoader.table.tolerance

        try await harness.loading.show(LoadingTestViewModel())
        let attachedFrame = try #require(harness.contentView).frame
        await harness.loading.hide()

        #expect(abs(Double(attachedFrame.minX) - (24 + 30)) <= tolerance, "実測 \(attachedFrame)")
        #expect(abs(Double(attachedFrame.minY) - (59 + 24)) <= tolerance, "実測 \(attachedFrame)")

        // 引数を渡すと添付はオブジェクトまるごと置換される (offsetX 30 も引き継がない)。
        try await harness.loading.show(
            LoadingTestViewModel(),
            placement: DialogPlacement(horizontalAlignment: .end, verticalAlignment: .end)
        )
        let argumentFrame = try #require(harness.contentView).frame
        await harness.loading.hide()

        let expectedRight = 390.0 - 24
        let expectedBottom = 844.0 - 34 - 24
        #expect(abs(Double(argumentFrame.maxX) - expectedRight) <= tolerance, "実測 \(argumentFrame)")
        #expect(abs(Double(argumentFrame.maxY) - expectedBottom) <= tolerance, "実測 \(argumentFrame)")
    }

    @Test("[LD-AT-03] 外側タップで閉じず、背後にも透過しない")
    func LD_AT_03_outsideTapNeitherClosesNorPassesThrough() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: Self.contentSize)
            // Loading では常に無効なので、真を添付しても外側タップは効かない。
            view.ksDialogOptions = DialogOptions(isCanceledOnTouchOutside: true)
            viewRecorder.record(view)
            return view
        }

        try await harness.loading.show(LoadingTestViewModel())
        let containerView = try #require(harness.containerView)

        // 実際のタップと同じ経路 (座標 → ヒットテスト) を通す。
        let touched = harness.window.hitTest(Self.outsidePoint, with: nil)
        #expect(touched === containerView, "外側のタップは覆いが吸収し、背後の画面へは届かない")
        #expect(touched !== harness.window.rootViewController?.view)

        // 外側タップを扱う口そのものが無いため、待っても閉じない。
        let closed = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) {
            harness.isPresenting == false
        }
        #expect(closed == false, "表示は閉じない")

        await harness.loading.hide()
    }

    @Test("[LD-AT-04] ダイアログ表示中の Loading は最前面で入力を遮る")
    func LD_AT_04_loadingIsFrontmostOverPresentedDialog() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        // ダイアログの器を取り付け先の window へ載せる。
        // シーンを持たないテスト実行環境では UIKit の提示遷移が完走せず、`present` では
        // ダイアログの View が window へ入らないため、本番の全画面提示と同じ位置
        // (window の subview) へ直接載せる置き方を使う (DialogTestPresentationSurface と同じ扱い)。
        let dialogContentView = FixedContentSizeView(contentSize: Self.contentSize)
        let dialogContainer = DialogContainerViewController(
            contentView: dialogContentView,
            resultChannel: DialogResultChannel()
        )
        dialogContainer.loadViewIfNeeded()
        dialogContainer.view.frame = harness.window.bounds
        harness.window.addSubview(dialogContainer.view)
        harness.window.layoutIfNeeded()
        try #require(dialogContainer.view.window === harness.window, "ダイアログが画面に載っている")

        await harness.loading.show()
        let loadingContainerView = try #require(harness.containerView)

        #expect(
            harness.window.subviews.last === loadingContainerView,
            "Loading はダイアログより手前に載る"
        )

        // ダイアログの中身の中心を突いても、受け取るのは Loading の器の側になる。
        let dialogCenter = dialogContentView.convert(
            CGPoint(x: dialogContentView.bounds.midX, y: dialogContentView.bounds.midY),
            to: harness.window
        )
        let touchedOverDialog = try #require(harness.window.hitTest(dialogCenter, with: nil))
        #expect(
            touchedOverDialog.isDescendant(of: loadingContainerView),
            "ダイアログへのタップも遮られる"
        )
        let touchedOutside = try #require(harness.window.hitTest(Self.outsidePoint, with: nil))
        #expect(touchedOutside.isDescendant(of: loadingContainerView))

        // Loading を閉じると、遮っていた入力はダイアログ側へ戻る。
        await harness.loading.hide()
        let touchedAfterHide = try #require(harness.window.hitTest(dialogCenter, with: nil))
        #expect(touchedAfterHide.isDescendant(of: dialogContainer.view))
        dialogContainer.view.removeFromSuperview()
    }

    @Test("[LD-AT-05] 設定プロパティの options 変更が次の表示から効く")
    func LD_AT_05_optionsSettingAppliesFromNextDisplay() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let overlayColor = UIColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        harness.loading.options = DialogOptions(
            overlayColor: overlayColor,
            isCanceledOnTouchOutside: true
        )

        await harness.loading.show()
        let container = try #require(harness.coordinator.presentedContainer)

        #expect(container.overlayView.backgroundColor == overlayColor, "変更後の色で覆いが描かれる")

        // isCanceledOnTouchOutside を設定しても外側タップは無効のまま。
        #expect(harness.window.hitTest(Self.outsidePoint, with: nil) === container.view)
        let closed = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) {
            harness.isPresenting == false
        }
        #expect(closed == false)

        await harness.loading.hide()
    }

    @Test("[LD-WN-01] 画面の変化をまたいで表示が継続し再配置される")
    func LD_WN_01_displaySurvivesGeometryChangeAndRelayouts() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        let viewRecorder = LoadingTestViewRecorder()
        harness.registry.register(LoadingTestViewModel.self) { _ in
            let view = FixedContentSizeView(contentSize: CGSize(width: 100, height: 100))
            // 比率と余白の両方が効く属性にして、寸法と余白どちらの変化も rect に現れるようにする。
            view.ksDialogOptions = DialogOptions(
                layoutArea: .visibleArea,
                dialogMargin: DialogEdgeInsets(all: 24),
                proportionalWidth: 0.5,
                proportionalHeight: 0.25
            )
            viewRecorder.record(view)
            return view
        }
        let gate = DialogTransitionGate()

        let scope = Task {
            try await harness.loading.start(LoadingTestViewModel()) { _ in try await gate.wait() }
        }
        try #require(await harness.waitUntilPresenting())
        let contentView = try #require(harness.contentView)
        let container = try #require(harness.coordinator.presentedContainer)

        // 縦向き: R = 390 x (844 - 59 - 34) = 390 x 751、A は各辺 24 控除、比率は R 基準。
        expectFrame(contentView, x: 97.5, y: 340.625, width: 195, height: 187.75)

        // 固定後に添付を書き換えても、回転後の再配置は固定済みの値で行われる。
        contentView.ksDialogOptions = DialogOptions(
            layoutArea: .window,
            dialogMargin: .zero,
            proportionalWidth: 0.9,
            proportionalHeight: 0.9
        )
        harness.changeGeometry(
            screen: DialogLayoutCase.Size(w: 844, h: 390),
            insets: DialogLayoutCase.Insets(top: 0, bottom: 21, left: 59, right: 59)
        )

        #expect(harness.isPresenting, "画面の変化をまたいで表示は継続する")
        // 横向き: R = (844 - 118) x (390 - 21) = 726 x 369。
        expectFrame(contentView, x: 240.5, y: 138.375, width: 363, height: 92.25)
        #expect(container.isLayoutSnapshotFrozen, "実効値の固定は解けない")

        gate.open()
        try await scope.value
        #expect(harness.isPresenting == false, "処理の完了で表示が消える")
    }

    /// 中身の矩形が期待値と一致することを、共通ケース表と同じ許容差で確かめる。
    private func expectFrame(
        _ contentView: UIView,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let tolerance = DialogLayoutCaseLoader.table.tolerance
        let actual = contentView.frame
        let detail = "期待 (x \(x), y \(y), w \(width), h \(height)) 実測 \(actual)"
        #expect(abs(Double(actual.minX) - x) <= tolerance, "x が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(Double(actual.minY) - y) <= tolerance, "y が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(Double(actual.width) - width) <= tolerance, "w が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(
            abs(Double(actual.height) - height) <= tolerance,
            "h が一致しない — \(detail)",
            sourceLocation: sourceLocation
        )
    }
}
#endif
