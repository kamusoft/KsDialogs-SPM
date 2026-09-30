#if canImport(UIKit)
/// 呼び出しの時点で取った、提示先を待つ列の順番札。
///
/// show の呼び出し口が UI スレッドへ処理を移す前に同期で取り、移った先の提示処理へ渡す。
/// 提示処理が列に着いた時点で札は列の待ちへ引き継がれる。列に着かずに終わった
/// (登録が無い・同じ ViewModel が表示中などで失敗した、札を使わずに捨てた) 場合は
/// `release()` か解放で手放され、後ろの show を止め続けない。
final class DialogHostWaitReservation: Sendable {
    /// 列の中の順番。小さいほど先に明ける。
    let ticket: UInt64

    private let queue: DialogHostWaitQueue

    init(ticket: UInt64, queue: DialogHostWaitQueue) {
        self.ticket = ticket
        self.queue = queue
    }

    /// この札を発行した列か。別の列に着いた場合は札を使わない。
    func belongs(to queue: DialogHostWaitQueue) -> Bool {
        self.queue === queue
    }

    /// 列に着いた。未着の控えから外し、以後は列の待ちがこの札の順番で並ぶ。
    func claim() -> UInt64 {
        _ = queue.ledger.settle(ticket)
        return ticket
    }

    /// 列に着かずに札を手放す。何度呼んでもよく、列に着いたあとは何もしない。
    func release() {
        guard queue.ledger.settle(ticket) else { return }
        // この札を待って止まっていた後ろの show を、UI スレッドで先へ進める。
        let queue = queue
        Task { @MainActor in
            queue.reservationWasReleased()
        }
    }

    deinit {
        release()
    }
}
#endif
