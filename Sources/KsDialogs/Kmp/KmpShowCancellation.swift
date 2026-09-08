#if canImport(UIKit)
import Foundation

/// show 1回分の取り消しを、提示の開始と待機の打ち切りのどちらが先に起きても取りこぼさずに受け渡す箱。
///
/// 呼び出し元 Task のキャンセルで当該ダイアログだけを閉鎖する契約 (kmp/ADR-0005) の実現機構。
/// 待機の打ち切りは提示が始まる前にも起こり得るため、先に取り消しが来た場合は
/// ハンドルが届いた時点で取り消す。任意のスレッドから触られるためロックで保護する。
final class KmpShowCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: KsDialogsInteropShowHandle?
    private var isCancelled = false

    /// 提示のハンドルを受け取る。すでに取り消されていればその場で取り消す。
    func attach(_ handle: KsDialogsInteropShowHandle) {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            handle.cancel()
            return
        }
        self.handle = handle
        lock.unlock()
    }

    /// 取り消しを要求する。ハンドルがまだ届いていなければ、届いた時点で取り消される。
    func cancel() {
        lock.lock()
        isCancelled = true
        let pendingHandle = handle
        handle = nil
        lock.unlock()
        pendingHandle?.cancel()
    }
}
#endif
