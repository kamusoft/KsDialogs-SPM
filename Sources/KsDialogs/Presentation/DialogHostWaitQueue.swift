#if canImport(UIKit)
/// 提示先の出現を待っている Dialog の列 (core/ADR-0041)。
///
/// 待っている Dialog は呼んだ順に並び、提示先が現れたら先頭の 1 枚ずつ明ける。明けた 1 枚の提示が
/// 終わるまでは次を明けないので、後から呼んだものが手前に重なり、提示の途中に次の提示を重ねない。
/// 列に待っている Dialog があるうちの新しい show は、提示先があっても後ろに並び、先に待っている
/// Dialog を追い越さない。
///
/// 列を持つのは OS に渡す前の待ちだけで、渡したあとの重なりは OS の提示の連なりに任せる
/// (core/ADR-0006)。提示先の出現の合図は、列が空でない間だけ 1 本購読する。
///
/// 列の順番は順番札 (`DialogHostWaitTicketLedger`) で決める。UI スレッドへ移る前に札を取る呼び出し口
/// (`reserve()`) では呼び出しの時点の順、それ以外は列に着いた時点の順になる。先に取られてまだ列に
/// 着いていない札がある間は、それより後の札の show を明けない。
///
/// 同じ提示先を共有する show は同じ列に並ぶ必要があるため、既定の提示面はすべて
/// `application` を使う。テスト用の提示面は、互いに干渉しないよう自分の列を持つ。
@MainActor
final class DialogHostWaitQueue {
    /// アプリケーションの提示先 (前面でアクティブなシーンの key window) を使う show が並ぶ列。
    nonisolated static let application = DialogHostWaitQueue()

    /// 列の順番札の台帳。任意のスレッドから札を取れるよう、UI スレッドの外に置く。
    nonisolated let ledger = DialogHostWaitTicketLedger()

    /// 待っている show (札の小さい順)。
    private var waiters: [DialogHostWaiter] = []

    /// 列から明けて、提示が終わっていない 1 枚の番。
    private var presentingSlot: DialogHostWaitSlot?

    /// 提示先の出現の合図の購読。列が空でない間だけ張る。
    private var registration: DialogHostAppearanceRegistration?

    nonisolated init() {}

    /// 待っている show の数。札を取ってまだ列に着いていない show も数える。
    var waitingCount: Int {
        waiters.count + ledger.pendingCount
    }

    /// 呼び出しの時点で順番札を取る。任意のスレッドから同期で呼べる。
    ///
    /// 札は `waitForTurn` に渡して列の順番に使う。使わずに終わるときは `release()` で手放す
    /// (手放し忘れても、札が解放された時点で手放される)。
    nonisolated func reserve() -> DialogHostWaitReservation {
        DialogHostWaitReservation(ticket: ledger.issue(pending: true), queue: self)
    }

    /// 提示してよくなるまで待つ。
    ///
    /// 列が空で、提示中の番も無く、先に取られた未着の札も無く、提示先があれば、待たずに提示へ進む。
    /// それ以外は札の順番で列に並び、提示先が現れて先頭に来た時点・結果が確定した時点
    /// (呼び出し元の打ち切りを含む) のどちらかで明ける。
    /// 打ち切りは結果チャネルの取り消しとして確定させ、確定と同じ経路で列から外す。
    /// - Parameters:
    ///   - surface: 提示に使う面。提示先の有無はこの面で読む
    ///   - resultChannel: この show の結果チャネル。待っている間の確定を観察する
    ///   - reservation: 呼び出しの時点で取った順番札。nil なら、列に着いたこの時点で札を取る
    func waitForTurn(
        surface: any DialogPresentationSurface,
        resultChannel: DialogResultChannel,
        reservation: DialogHostWaitReservation? = nil
    ) async -> DialogHostWaitTurn {
        let ticket: UInt64
        if let reservation, reservation.belongs(to: self) {
            ticket = reservation.claim()
        } else {
            // 別の列の札は、この列の順番には使えない。
            reservation?.release()
            ticket = ledger.issue(pending: false)
        }
        if waiters.isEmpty, presentingSlot == nil, !ledger.hasPendingTicket(before: ticket), surface.canPresent {
            return .ready(nil)
        }
        while true {
            // 明けたあとに提示先が消えて待ち直すときも、同じ札で並ぶので順番は変わらない。
            let waiter = DialogHostWaiter(surface: surface, ticket: ticket)
            let turn = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<DialogHostWaitTurn, Never>) in
                    waiter.attach(continuation)
                    enqueue(waiter)
                    // 確定の通知は任意のスレッドから届くので、UI スレッドへ移してから列を操作する。
                    resultChannel.observeSettlement { [weak self] in
                        Task { @MainActor in
                            self?.withdraw(waiter)
                        }
                    }
                }
            } onCancel: {
                // 呼び出し元の打ち切りは、キャンセルとして結果を確定させる。
                resultChannel.cancelFromCaller()
            }
            resultChannel.removeSettlementObserver()
            guard case .ready(let slot) = turn else {
                return .settled
            }
            // 明けた直後に、待ちの間の確定 (呼び出し元の打ち切りを含む) が無いかを確かめる。
            if resultChannel.isResultSettled {
                slot?.finish()
                return .settled
            }
            if surface.canPresent {
                return turn
            }
            // 明けてからここへ戻るまでの間に提示先が消えた。同じ札で待ち直すので、順番は保たれる。
            slot?.relinquish()
        }
    }

    /// 番を持っていた 1 枚の提示が終わった。
    func slotDidFinish(_ slot: DialogHostWaitSlot, advances: Bool) {
        guard presentingSlot === slot else { return }
        presentingSlot = nil
        if advances {
            advance()
        }
    }

    /// 札が取られたまま列に着かずに手放された。その札を待って止まっていた先頭を先へ進める。
    func reservationWasReleased() {
        advance()
    }

    /// 札の順番の位置に並べ、合図の購読を用意する。
    private func enqueue(_ waiter: DialogHostWaiter) {
        let index = waiters.firstIndex { $0.ticket > waiter.ticket } ?? waiters.endIndex
        waiters.insert(waiter, at: index)
        if registration == nil {
            registration = waiter.surface.observeHostAppearance { [weak self] in
                self?.advance()
            }
        }
        // 合図を待たずに提示先が既にある場合 (提示中の番が無いのに列が残っていた場合) も先へ進める。
        advance()
    }

    /// 結果が確定した show を、順番を待たずに列から外す。明けたあとなら何もしない。
    private func withdraw(_ waiter: DialogHostWaiter) {
        guard let index = waiters.firstIndex(where: { $0 === waiter }) else { return }
        waiters.remove(at: index)
        releaseRegistrationIfIdle()
        waiter.resume(.settled)
        // 先頭が外れたことで、次の 1 枚が明けられるようになっていれば明ける。
        advance()
    }

    /// 提示先があり、提示中の番も、先頭より前に取られた未着の札も無ければ、列の先頭の 1 枚だけを明ける。
    private func advance() {
        guard presentingSlot == nil, let head = waiters.first else { return }
        guard !ledger.hasPendingTicket(before: head.ticket) else { return }
        // 合図は「現れたかもしれない」ことだけを知らせるので、提示先を読み直す。
        guard head.surface.canPresent else { return }
        waiters.removeFirst()
        let slot = DialogHostWaitSlot(queue: self)
        presentingSlot = slot
        releaseRegistrationIfIdle()
        head.resume(.ready(slot))
    }

    /// 待っている show が無くなったら、合図の購読を解除する。
    private func releaseRegistrationIfIdle() {
        guard waiters.isEmpty else { return }
        registration?.cancel()
        registration = nil
    }
}
#endif
