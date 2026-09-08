#if canImport(UIKit)
import Foundation

/// フックの完了までの間をテストから制御するための門。
///
/// `wait()` は `open()` が呼ばれるまで戻らない。待っている間にキャンセルされたら
/// `CancellationError` を投げるので、器の脱出口が働いたことを待ち側から観察できる。
@MainActor
final class DialogTransitionGate {
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var isOpen = false

    /// 門を開け、待っている呼び出しをすべて通す。以後の `wait()` は即座に戻る。
    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters = [:]
        for continuation in pending.values {
            continuation.resume()
        }
    }

    /// 門が開くまで待つ。
    func wait() async throws {
        guard !isOpen else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if isOpen {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.abandon(id)
            }
        }
    }

    /// 待っている1件をキャンセルとして打ち切る。
    private func abandon(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
    }
}
#endif
