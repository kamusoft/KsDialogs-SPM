#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// Toast の完全非対話と非モーダルの契約 (core/ADR-0031) を確かめる。
///
/// Toast の面へのタッチは背後のページ要素へ素通しされ、Toast 自身はタップで消えない。
/// カスタム View の中に対話可能な部品を置いても反応しない。
@Suite("Toast の完全非対話と非モーダル", .serialized)
@MainActor
struct ToastNonModalTests {
    /// 素通しの観察中に期限が来ないだけの長さ。
    private static let longDuration = 5000

    @Test("[TS-NM-01] Toast の真下の要素が操作できる")
    func TS_NM_01_touchPassesThroughToElementBehind() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let rootView = try #require(harness.window.rootViewController?.view)
        let button = UIControl(frame: rootView.bounds)
        rootView.addSubview(button)

        harness.toast.show(message: "重なる位置の Toast", duration: Self.longDuration)
        try #require(await harness.waitUntilPresenting())

        let contentView = try #require(harness.contentViews.first)
        harness.window.layoutIfNeeded()
        let touchPoint = contentView.convert(
            CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY),
            to: harness.window
        )

        let hit = harness.window.hitTest(touchPoint, with: nil)

        #expect(hit === button, "Toast と重なる位置のタッチは背後の要素に当たる")
        #expect(harness.displayCount == 1, "タップでは消えない")
    }

    @Test("[TS-NM-02] カスタム View 内の対話部品は反応しない")
    func TS_NM_02_interactiveContentInCustomViewDoesNotRespond() async throws {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        let rootView = try #require(harness.window.rootViewController?.view)
        let background = UIControl(frame: rootView.bounds)
        rootView.addSubview(background)

        let embeddedButton = UIButton(type: .system)
        try harness.toast.show(ToastTestViewModel(), duration: Self.longDuration) { _ in
            let container = FixedContentSizeView(contentSize: CGSize(width: 200, height: 60))
            embeddedButton.setTitle("押せない", for: .normal)
            embeddedButton.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(embeddedButton)
            NSLayoutConstraint.activate([
                embeddedButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                embeddedButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return container
        }

        try #require(await harness.waitUntilPresenting())
        harness.window.layoutIfNeeded()
        let touchPoint = embeddedButton.convert(
            CGPoint(x: embeddedButton.bounds.midX, y: embeddedButton.bounds.midY),
            to: harness.window
        )

        let hit = harness.window.hitTest(touchPoint, with: nil)

        #expect(hit === background, "カスタム View の部品ではなく背後の要素に当たる")
        #expect(hit !== embeddedButton)
        #expect(harness.displayCount == 1, "対話部品へのタップでも消えない")
    }
}
#endif
