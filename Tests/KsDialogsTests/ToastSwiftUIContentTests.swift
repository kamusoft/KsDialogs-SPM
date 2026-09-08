#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// SwiftUI で書いたカスタム Toast が従来 View 系と同じに働くことを確かめる (core/ADR-0010・0011)。
///
/// 中身を書く技術で観察可能な挙動 (表示・配置・消滅) は変わらない。
@Suite("SwiftUI のカスタム Toast", .serialized)
@MainActor
struct ToastSwiftUIContentTests {
    /// 両系統に同じ内容サイズを要求させ、位置とサイズの比較を成立させる。
    private static let contentSize = CGSize(width: 200, height: 60)

    @Test("[TS-IO-02] SwiftUI 登録のカスタム Toast が UIKit 登録と同じに働く")
    func TS_IO_02_swiftUIRegistrationMatchesUIKit() async throws {
        let uiKitFrame = try await Self.measureRegisteredToastFrame { registry in
            registry.register(ToastTestViewModel.self) { _ in
                FixedContentSizeView(contentSize: Self.contentSize)
            }
        }
        let swiftUIFrame = try await Self.measureRegisteredToastFrame { registry in
            registry.register(ToastTestViewModel.self) { _ in
                Color.clear.frame(width: Self.contentSize.width, height: Self.contentSize.height)
            }
        }

        #expect(abs(swiftUIFrame.minX - uiKitFrame.minX) <= 1, "配置が一致する")
        #expect(abs(swiftUIFrame.minY - uiKitFrame.minY) <= 1)
        #expect(abs(swiftUIFrame.width - uiKitFrame.width) <= 1, "サイズが一致する")
        #expect(abs(swiftUIFrame.height - uiKitFrame.height) <= 1)
    }

    /// 登録した中身で1枚表示し、レイアウト完了後の矩形を測ってから消えるまで見届ける。
    private static func measureRegisteredToastFrame(
        register: (ToastViewRegistry) -> Void
    ) async throws -> CGRect {
        let harness = ToastTestHarness()
        defer { harness.tearDown() }
        register(harness.registry)

        try harness.toast.show(ToastTestViewModel(), duration: 400)
        try #require(await harness.waitUntilPresenting())
        harness.window.layoutIfNeeded()
        let contentView = try #require(harness.contentViews.first)
        let frame = contentView.frame

        #expect(await harness.waitUntilEmpty(), "消滅の挙動も一致する")
        #expect(contentView.window == nil)
        return frame
    }
}
#endif
