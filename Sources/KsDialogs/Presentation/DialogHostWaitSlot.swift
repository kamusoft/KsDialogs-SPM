#if canImport(UIKit)
/// 提示先を待つ列から明けた 1 枚が持つ、提示の番。
///
/// 番を持っている間、列の次の 1 枚は明けない。提示が終わった (提示面の完了通知が届いた)
/// ときか、提示に進まずに show が終わったときに `finish()` で返す。
@MainActor
final class DialogHostWaitSlot {
    private weak var queue: DialogHostWaitQueue?

    init(queue: DialogHostWaitQueue) {
        self.queue = queue
    }

    /// 番を返し、提示先があれば列の次の 1 枚を明けさせる。何度呼んでもよく、2 回目以降は何もしない。
    func finish() {
        guard let queue else { return }
        self.queue = nil
        queue.slotDidFinish(self, advances: true)
    }

    /// 次の 1 枚を明けさせずに番を返す。明けた直後に提示先が消えていて、列の先頭へ戻るときに使う。
    func relinquish() {
        guard let queue else { return }
        self.queue = nil
        queue.slotDidFinish(self, advances: false)
    }
}
#endif
