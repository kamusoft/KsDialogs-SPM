#if canImport(UIKit)
import SwiftUI
import Testing

/// SwiftUI の中身の一番外側の View から見えた安全領域と矩形 (window 座標) を、届いた順に記録する。
@MainActor
final class SwiftUISafeAreaRecord {
    private(set) var insets: [EdgeInsets] = []
    private(set) var frames: [CGRect] = []

    var latestInsets: EdgeInsets? { insets.last }
    var latestFrame: CGRect? { frames.last }

    func record(insets value: EdgeInsets) {
        insets.append(value)
    }

    func record(frame value: CGRect) {
        frames.append(value)
    }

    /// 最後に見えた安全領域が、辺ごとに期待値と許容誤差の内で一致するか。
    func latestInsetsMatch(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) -> Bool {
        guard let latest = latestInsets else { return false }
        return abs(latest.top - top) <= 0.5
            && abs(latest.leading - leading) <= 0.5
            && abs(latest.bottom - bottom) <= 0.5
            && abs(latest.trailing - trailing) <= 0.5
    }

    /// 失敗時の説明に添える、届いた安全領域の履歴。
    var insetsHistory: String {
        insets.map { "t\($0.top) l\($0.leading) b\($0.bottom) r\($0.trailing)" }.joined(separator: " → ")
    }

    /// 少し待ったあとで、これまでに届いた安全領域が 1 度も 0 以外にならなかったことを確かめる。
    /// 「受け取らない」は最後の値だけでなく、途中に一瞬届いた値も含めて見る。
    func expectNoInsetsEver(_ note: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        let arrived = await DialogTestWaiting.waitUntil(timeout: .seconds(2)) { !self.insets.isEmpty }
        try? await Task.sleep(for: .milliseconds(300))
        let isZero: (EdgeInsets) -> Bool = {
            abs($0.top) <= 0.5 && abs($0.leading) <= 0.5 && abs($0.bottom) <= 0.5 && abs($0.trailing) <= 0.5
        }
        #expect(arrived, "\(note) — 安全領域が 1 度も届かなかった", sourceLocation: sourceLocation)
        #expect(
            insets.allSatisfy(isZero),
            "\(note) — 安全領域を受け取らないはずが、届いた履歴 \(insetsHistory)",
            sourceLocation: sourceLocation
        )
    }

    /// 最後に見えた安全領域が期待値になるまで待ち、ならなければ履歴を添えて失敗を記録する。
    /// 安全領域は SwiftUI の更新の中で届くため、器の実効値が固まった時点ではまだ古いことがある。
    func expectLatestInsets(
        top: CGFloat = 0,
        leading: CGFloat = 0,
        bottom: CGFloat = 0,
        trailing: CGFloat = 0,
        _ note: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let matched = await DialogTestWaiting.waitUntil(timeout: .seconds(2)) {
            self.latestInsetsMatch(top: top, leading: leading, bottom: bottom, trailing: trailing)
        }
        #expect(
            matched,
            "\(note) — 期待 t\(top) l\(leading) b\(bottom) r\(trailing)、届いた履歴 \(insetsHistory)",
            sourceLocation: sourceLocation
        )
    }
}
#endif
