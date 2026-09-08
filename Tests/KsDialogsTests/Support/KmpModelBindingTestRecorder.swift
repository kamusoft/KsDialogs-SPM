#if canImport(UIKit)
import Testing

@testable import KsDialogs

/// KMP 面の1引数 factory が生成した中身を記録する。
///
/// 生成の有無と、生成時点で引けた結果報告口を、表示された中身の側から観察するために使う。
@MainActor
final class KmpModelBindingTestRecorder<Result: Sendable> {
    /// 生成された中身 (生成順)。
    private(set) var createdViews: [KmpModelBindingTestContentView<Result>] = []

    /// 生成された中身を記録してそのまま返す。
    func recording(
        _ view: KmpModelBindingTestContentView<Result>
    ) -> KmpModelBindingTestContentView<Result> {
        createdViews.append(view)
        return view
    }

    /// index 番目の中身が生成されるまで待って返す。
    func view(at index: Int) async throws -> KmpModelBindingTestContentView<Result> {
        let appeared = await DialogTestWaiting.waitUntil { self.createdViews.count > index }
        try #require(appeared, "index \(index) の中身が生成されなかった")
        return createdViews[index]
    }
}
#endif
