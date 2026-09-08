#if canImport(UIKit)
import Foundation

/// 提示・結果確定のような非同期の状態変化を待ち合わせるための補助。
enum DialogTestWaiting {
    /// 条件が満たされるまで待つ。時間切れになったら false を返す。
    @MainActor
    static func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
#endif
