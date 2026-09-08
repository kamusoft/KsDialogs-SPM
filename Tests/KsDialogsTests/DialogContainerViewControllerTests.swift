#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

@Suite("ダイアログの器の組み立て", .serialized)
@MainActor
struct DialogContainerViewControllerTests {
    @Test("中身の View が覆いの上に配置される")
    func contentViewIsPlacedOverBackdrop() {
        let contentView = DialogTestContentView()
        let container = DialogContainerViewController(
            contentView: contentView,
            resultChannel: DialogResultChannel()
        )

        container.loadViewIfNeeded()

        #expect(contentView.superview === container.view)
        #expect(contentView.translatesAutoresizingMaskIntoConstraints == false)
        var backdropAlpha: CGFloat = 0
        container.overlayView.backgroundColor?.getWhite(nil, alpha: &backdropAlpha)
        #expect(backdropAlpha > 0)
    }

    @Test("器が画面から外れたら未確定の結果は cancelled になる")
    func disappearanceSettlesUnresolvedResult() async {
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: resultChannel
        )
        container.loadViewIfNeeded()

        container.beginAppearanceTransition(false, animated: false)
        container.endAppearanceTransition()

        #expect(await DialogTestWaiting.waitUntil { resultChannel.isResultSettled })
        #expect(recorder.count == 1)
        #expect(recorder.isFirstCancelled)
    }

    @Test("上に別の画面が重なっただけでは結果は確定しない")
    func coveringPresentationKeepsResultUnresolved() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let rootViewController = UIViewController()
        window.rootViewController = rootViewController
        window.isHidden = false
        defer { window.isHidden = true }
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: resultChannel
        )
        rootViewController.present(container, animated: false)
        container.loadViewIfNeeded()
        try #require(container.presentingViewController != nil)
        #expect(recorder.count == 0, "提示の直後に確定していないこと")

        // 器の上に全画面の画面が重なった状況 (器はまだ提示の連なりに載っている)。
        container.beginAppearanceTransition(false, animated: false)
        container.endAppearanceTransition()

        let settled = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) {
            resultChannel.isResultSettled
        }
        #expect(settled == false)
        #expect(recorder.count == 0)
    }

    @Test("確定済みの器が画面から外れても結果は変わらない")
    func disappearanceKeepsAlreadySettledResult() async {
        let resultChannel = DialogResultChannel()
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }
        let container = DialogContainerViewController(
            contentView: DialogTestContentView(),
            resultChannel: resultChannel
        )
        container.loadViewIfNeeded()
        resultChannel.settle(.completed(true))

        container.beginAppearanceTransition(false, animated: false)
        container.endAppearanceTransition()
        _ = await DialogTestWaiting.waitUntil(timeout: .milliseconds(300)) { recorder.count > 1 }

        #expect(recorder.count == 1)
        #expect(recorder.firstCompletedValue(as: Bool.self) == true)
    }
}
#endif
