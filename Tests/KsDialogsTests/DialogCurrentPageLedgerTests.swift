#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// modifier が名乗らせた View の台帳の規則を、UIKit の目印 View を直接出し入れして確かめる。
///
/// 画面へ載る順番をテストが決められるよう SwiftUI を通さず、台帳もテストごとに新しく作る。
/// SwiftUI の modifier を通した結線は `DialogCurrentPageSwiftUITests` が確かめる。
@Suite("現在ページの台帳の規則", .serialized)
@MainActor
struct DialogCurrentPageLedgerTests {
    private typealias Stage = DialogCurrentPageStage

    /// 台帳・ウィンドウ・ページの土台になる root の View の組。
    @MainActor
    private struct Fixture {
        let ledger = DialogCurrentPageLedger()
        let window = Stage.makeWindow(rootViewController: UIViewController())

        var rootView: UIView {
            window.rootViewController!.view
        }

        /// 目印を root の View へ載せる (載った時点で台帳に載る)。
        @discardableResult
        func placeMarker(_ frame: CGRect, in parent: UIView? = nil) -> DialogCurrentPageMarkerView {
            let marker = DialogCurrentPageMarkerView(ledger: ledger)
            marker.frame = frame
            (parent ?? rootView).addSubview(marker)
            return marker
        }

        func lookUp() -> DialogCurrentPageLookup {
            ledger.lookUpPageRect(in: window)
        }
    }

    @Test("1 つだけ名乗ったときはその枠の矩形が基準になる")
    func singleMarkerIsUsed() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let frame = CGRect(x: 0, y: 100, width: 400, height: 500)

        fixture.placeMarker(frame)

        #expect(fixture.lookUp() == .found(frame))
    }

    @Test("名乗った枠が画面から外れると台帳から外れ、候補が無くなる")
    func detachedMarkerIsRemoved() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let marker = fixture.placeMarker(CGRect(x: 0, y: 100, width: 400, height: 500))

        marker.removeFromSuperview()

        #expect(fixture.ledger.attachedViewCount == 0)
        guard case .notFound = fixture.lookUp() else {
            Issue.record("画面から外れた枠が候補に残っている")
            return
        }
    }

    @Test("画面へ戻った枠は再び基準になる")
    func reattachedMarkerIsUsedAgain() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let frame = CGRect(x: 0, y: 100, width: 400, height: 500)
        let marker = fixture.placeMarker(frame)
        marker.removeFromSuperview()

        fixture.rootView.addSubview(marker)

        #expect(fixture.lookUp() == .found(frame))
    }

    @Test("入れ子の枠は、後から外側が載っても内側が勝つ")
    func innerMarkerWinsOverOuter() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let inner = CGRect(x: 20, y: 150, width: 360, height: 300)
        fixture.placeMarker(inner)

        fixture.placeMarker(CGRect(x: 0, y: 100, width: 400, height: 500))

        #expect(fixture.lookUp() == .found(inner))
    }

    @Test("入れ子でない枠どうしは最後に載ったものが勝つ")
    func lastPlacedMarkerWins() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        fixture.placeMarker(CGRect(x: 0, y: 100, width: 400, height: 300))
        let later = CGRect(x: 0, y: 300, width: 400, height: 300)

        fixture.placeMarker(later)

        #expect(fixture.lookUp() == .found(later))
    }

    @Test("最後に載った枠が外れると、残りの候補で決め直す")
    func removingLatestFallsBackToRemaining() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let earlier = CGRect(x: 0, y: 100, width: 400, height: 300)
        fixture.placeMarker(earlier)
        let later = fixture.placeMarker(CGRect(x: 0, y: 300, width: 400, height: 300))

        later.removeFromSuperview()

        #expect(fixture.lookUp() == .found(earlier))
    }

    @Test("窓の外に置かれた枠は、後から載っても候補にならない")
    func markerOutsideWindowIsIgnored() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let inside = CGRect(x: 0, y: 100, width: 400, height: 500)
        fixture.placeMarker(inside)

        // 隣のページのように、横へ 1 画面ぶんずれた位置に置かれた枠。
        fixture.placeMarker(CGRect(x: Stage.screen.w, y: 100, width: 400, height: 500))

        #expect(fixture.lookUp() == .found(inside))
    }

    @Test("別のウィンドウに載った枠は、後から載っても候補にならない")
    func markerInAnotherWindowIsIgnored() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let otherWindow = Stage.makeWindow(rootViewController: UIViewController())
        defer { otherWindow.isHidden = true }
        let inside = CGRect(x: 0, y: 100, width: 400, height: 500)
        fixture.placeMarker(inside)

        fixture.placeMarker(CGRect(x: 0, y: 200, width: 400, height: 300), in: otherWindow.rootViewController!.view)

        #expect(fixture.lookUp() == .found(inside))
    }

    @Test("非表示の祖先を持つ枠は、内側にあっても候補にならない")
    func markerUnderHiddenAncestorIsSkipped() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let outer = CGRect(x: 0, y: 50, width: 400, height: 720)
        fixture.placeMarker(outer)
        let hiddenParent = UIView(frame: fixture.rootView.bounds)
        fixture.rootView.addSubview(hiddenParent)
        fixture.placeMarker(CGRect(x: 0, y: 100, width: 400, height: 600), in: hiddenParent)

        hiddenParent.isHidden = true

        #expect(fixture.ledger.attachedViewCount == 2, "ウィンドウに載ったままなので台帳には残る")
        #expect(fixture.lookUp() == .found(outer))
    }

    @Test("不透明度 0 の祖先を持つ枠は候補にならず、不透明度が戻ると再び候補になる")
    func markerUnderTransparentAncestorIsSkippedUntilOpaque() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let outer = CGRect(x: 0, y: 50, width: 400, height: 720)
        let inner = CGRect(x: 0, y: 100, width: 400, height: 600)
        fixture.placeMarker(outer)
        let fadingParent = UIView(frame: fixture.rootView.bounds)
        fixture.rootView.addSubview(fadingParent)
        fixture.placeMarker(inner, in: fadingParent)

        fadingParent.alpha = 0
        #expect(fixture.lookUp() == .found(outer))

        fadingParent.alpha = 1
        #expect(fixture.lookUp() == .found(inner))
    }

    @Test("台帳が空のときは未解決になり、器の基準は既定の取得元も無ければ visibleArea と一致する")
    func emptyLedgerFallsBackToVisibleArea() {
        let fixture = Fixture()
        defer { fixture.window.isHidden = true }
        let marker = fixture.placeMarker(CGRect(x: 0, y: 100, width: 400, height: 500))
        marker.removeFromSuperview()
        // 既定の取得元を外し、台帳だけを取得元にした器で確かめる。
        let resolver = DialogCurrentPageResolver(sources: [fixture.ledger])
        let contentView = FixedContentSizeView(contentSize: Stage.contentSize)
        contentView.ksDialogOptions = DialogOptions(layoutArea: .currentPage)
        contentView.ksDialogPlacement = Stage.endEnd
        let applier = DialogLayoutApplier(contentView: contentView, currentPageResolver: resolver)
        let containerView = UIView(frame: fixture.window.bounds)
        applier.install(in: containerView)
        let layout = DialogLayout(options: DialogOptions(layoutArea: .currentPage), placement: Stage.endEnd)
        applier.rebuildConstraints(for: layout)
        fixture.window.addSubview(containerView)
        applier.updateForCurrentBounds(layout: layout)
        containerView.layoutIfNeeded()

        Stage.expectFrame(contentView, Stage.endEndFrame(in: Stage.visibleRect), "visibleArea と同じ位置")
        #expect(applier.currentPageDiagnostics.count == 1)
    }
}
#endif
