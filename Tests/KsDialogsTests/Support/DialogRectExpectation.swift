#if canImport(UIKit)
import Testing
import UIKit

/// 実測した rect を期待 rect と突き合わせる。
/// 比較の許容誤差は共通ケース表が持つ値を使い、テスト側で別の基準を作らない。
enum DialogRectExpectation {
    @MainActor
    static func expect(
        _ actual: CGRect,
        equals expected: CGRect,
        _ note: String = "",
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let tolerance = DialogLayoutCaseLoader.table.tolerance
        let detail = note.isEmpty ? "期待 \(expected) 実測 \(actual)" : "\(note) — 期待 \(expected) 実測 \(actual)"
        #expect(abs(Double(actual.minX - expected.minX)) <= tolerance, "x が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(Double(actual.minY - expected.minY)) <= tolerance, "y が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(Double(actual.width - expected.width)) <= tolerance, "w が一致しない — \(detail)", sourceLocation: sourceLocation)
        #expect(abs(Double(actual.height - expected.height)) <= tolerance, "h が一致しない — \(detail)", sourceLocation: sourceLocation)
    }
}
#endif
