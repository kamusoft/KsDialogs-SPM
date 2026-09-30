#if canImport(UIKit)
import os

/// 提示先を待つ列の順番札の台帳。
///
/// 札の番号は発行した順に大きくなり、列は札の小さいものから明ける。札は任意のスレッドから
/// 同期で発行できるので、呼び出しの時点で順番を決め、実際に列へ着くのが後になっても
/// その順番を保てる。発行済みで、まだ列に着いていない (手放されてもいない) 札を「未着」として控え、
/// 未着の札より大きい札の show は、未着の札を追い越して明けない。
final class DialogHostWaitTicketLedger: Sendable {
    private struct State {
        var nextTicket: UInt64 = 0
        var pendingTickets: Set<UInt64> = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// 新しい札を発行する。`pending` が true なら、列に着くまで未着として控える。
    func issue(pending: Bool) -> UInt64 {
        state.withLock { state in
            let ticket = state.nextTicket
            state.nextTicket += 1
            if pending {
                state.pendingTickets.insert(ticket)
            }
            return ticket
        }
    }

    /// 未着の札を控えから外す。控えにあった (まだ着いても手放されてもいなかった) ときだけ true を返す。
    func settle(_ ticket: UInt64) -> Bool {
        state.withLock { state in
            state.pendingTickets.remove(ticket) != nil
        }
    }

    /// 指定の札より前に発行された未着の札があるか。
    func hasPendingTicket(before ticket: UInt64) -> Bool {
        state.withLock { state in
            state.pendingTickets.contains { $0 < ticket }
        }
    }

    /// 未着の札の数。
    var pendingCount: Int {
        state.withLock { $0.pendingTickets.count }
    }
}
#endif
