#if canImport(UIKit)
import Foundation

/// 任意スレッドから来る Loading の受理を、UI スレッド上で呼ばれた順に直列化する待ち行列。
///
/// 受理のたびに独立した `Task` を立てると、受理どうしの順序も、受理と終了処理の順序も保証されない。
/// そのため「進捗を報告した直後に処理が戻る」形では、最終報告が終了処理に追い越されて
/// 旧世代の報告として捨てられうる。
///
/// ここでは直前の受理の完了を待ってから次を受理する鎖を組み、`drain()` で発行済みの受理を
/// すべて待てるようにする。積む操作は任意スレッドから行える。
final class LoadingReportQueue: @unchecked Sendable {
    /// 鎖の末尾の付け替えだけを守る錠。受理そのものは UI スレッド上で行われる。
    private let lock = NSLock()

    /// 鎖の末尾。最後に積まれた受理。
    private var tail: Task<Void, Never>?

    /// 受理を1件、鎖の末尾に積む。積んだ順に UI スレッド上で実行される。
    func enqueue(_ work: @escaping @MainActor @Sendable () async -> Void) {
        lock.withLock {
            let previous = tail
            tail = Task { @MainActor in
                await previous?.value
                await work()
            }
        }
    }

    /// ここまでに積まれた受理をすべて待つ。
    func drain() async {
        let pending = lock.withLock { tail }
        await pending?.value
    }
}
#endif
