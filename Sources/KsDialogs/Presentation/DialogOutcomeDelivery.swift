#if canImport(UIKit)

/// 撤去まで進んだ結果を呼び出し元へ届ける口。
///
/// 器とは別の寿命を持つ。器が撤去の完了を待っている間に提示機構が器を手放しても、
/// 待っている呼び出し元が取り残されないようにするためで、口を器の中に置くと
/// 器の解放と同時に配送先も失われる。
///
/// 配送は先に届いた1回だけ行う。器は撤去まで進んだ時点で `submitLatchedOutcome()` を呼び、
/// 撤去まで進めないまま解放されるときも同じ口から配送する (core/ADR-0017)。
@MainActor
final class DialogOutcomeDelivery {
    /// 結果がまだ確定していないときに、器の消失として確定させるためのチャネル。
    private let resultChannel: DialogResultChannel

    /// 結果の届け先。まだ決まっていなければ nil。
    private var destination: ((DialogOutcome) -> Void)?

    /// 届け先が決まる前に配送を求められた結果。届け先が決まった時点で配送する。
    private var pendingOutcome: DialogOutcome?

    /// 結果を配送したか。
    private(set) var isDelivered = false

    init(resultChannel: DialogResultChannel) {
        self.resultChannel = resultChannel
    }

    /// 結果の届け先を決める。配送を求められた結果が既にあればその場で届ける。
    func setDestination(_ destination: @escaping (DialogOutcome) -> Void) {
        // 届け先は配送より前に 1 回だけ決まる前提 (提示層が show の開始時に設定する)。
        // 配送済みの後に届け先が来る経路は無い。もし来ても結果は既に届いているので、
        // 新しい届け先を黙って捨てる (再配送はしない)。
        guard !isDelivered else { return }
        self.destination = destination
        deliverIfPossible()
    }

    /// 確定済みの結果を配送する。未確定なら器の消失として確定させてから配送する。
    /// 配送済み・配送待ちのときは何もしない。
    func submitLatchedOutcome() {
        guard !isDelivered, pendingOutcome == nil else { return }
        resultChannel.settle(.cancelled, origin: .hostLost)
        guard let outcome = resultChannel.settledOutcome else { return }
        pendingOutcome = outcome
        deliverIfPossible()
    }

    /// 結果と届け先が揃っていれば配送する。
    private func deliverIfPossible() {
        guard let outcome = pendingOutcome, let destination else { return }
        pendingOutcome = nil
        self.destination = nil
        isDelivered = true
        destination(outcome)
    }
}
#endif
