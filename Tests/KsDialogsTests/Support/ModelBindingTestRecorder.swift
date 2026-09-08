#if canImport(UIKit)
import SwiftUI
import Testing

@testable import KsDialogs

/// 中身の生成を記録する。生成の有無・順序と、生成時点で読めた値を観察するために使う。
@MainActor
final class ModelBindingTestRecorder {
    /// 生成された従来 View 系の中身 (生成順)。
    private(set) var createdViews: [ModelBindingTestContentView] = []

    /// SwiftUI の中身の生成時に読んだ ViewModel の状態 (生成順)。
    private(set) var observedMessages: [String] = []

    /// SwiftUI の中身の生成時に ViewModel から取り出した結果報告口 (生成順)。
    private(set) var suppliedNotifiers: [DialogNotifier<Bool>?] = []

    /// 中身の生成回数 (従来 View 系・SwiftUI の合計)。
    var creationCount: Int {
        createdViews.count + observedMessages.count
    }

    /// 生成された中身を記録してそのまま返す。
    func recording(_ view: ModelBindingTestContentView) -> ModelBindingTestContentView {
        createdViews.append(view)
        return view
    }

    /// SwiftUI の中身の生成を記録して、組み立てた中身をそのまま返す。
    func recording<Content: View>(
        message: String,
        notifier: DialogNotifier<Bool>?,
        content: Content
    ) -> Content {
        observedMessages.append(message)
        suppliedNotifiers.append(notifier)
        return content
    }

    /// index 番目の中身が生成されるまで待って返す。
    func view(at index: Int) async throws -> ModelBindingTestContentView {
        let appeared = await DialogTestWaiting.waitUntil { self.createdViews.count > index }
        try #require(appeared, "index \(index) の中身が生成されなかった")
        return createdViews[index]
    }

    /// index 番目の SwiftUI の中身が生成されるまで待って、そのとき読んだ状態を返す。
    func observedMessage(at index: Int) async throws -> String {
        let appeared = await DialogTestWaiting.waitUntil { self.observedMessages.count > index }
        try #require(appeared, "index \(index) の SwiftUI の中身が生成されなかった")
        return observedMessages[index]
    }

    /// index 番目の SwiftUI の中身が ViewModel から取り出した結果報告口を返す。
    func suppliedNotifier(at index: Int) async throws -> DialogNotifier<Bool> {
        let appeared = await DialogTestWaiting.waitUntil { self.suppliedNotifiers.count > index }
        try #require(appeared, "index \(index) の SwiftUI の中身が生成されなかった")
        return try #require(suppliedNotifiers[index], "中身の生成中に報告口が引けること")
    }
}
#endif
