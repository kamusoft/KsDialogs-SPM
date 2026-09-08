import Foundation

@testable import KsDialogs

/// 結果チャネルへ流れた確定結果を記録する。任意のスレッドからの報告を受けるためロックで保護する。
final class DialogOutcomeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [DialogOutcome] = []

    func record(_ outcome: DialogOutcome) {
        lock.lock()
        defer { lock.unlock() }
        outcomes.append(outcome)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return outcomes.count
    }

    /// 最初の確定結果が completed なら、その値を指定型として返す。
    func firstCompletedValue<Value>(as valueType: Value.Type) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard case .completed(let value) = outcomes.first else { return nil }
        return value as? Value
    }

    /// 最初の確定結果が cancelled かどうか。
    var isFirstCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .cancelled = outcomes.first { return true }
        return false
    }
}
