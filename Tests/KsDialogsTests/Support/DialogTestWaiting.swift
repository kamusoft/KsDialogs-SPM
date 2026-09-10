#if canImport(UIKit)
import Foundation
import Testing

/// 提示・結果確定のような非同期の状態変化を待ち合わせるための補助。
enum DialogTestWaiting {

    /// 落ち着きを認めるまでに観測が成り立ち続ける時間。60Hz の 3 フレーム弱に当たる。
    static let defaultStable = Duration.milliseconds(48)

    /// 観測を読み直す間隔。
    private static let pollingInterval = Duration.milliseconds(5)

    /// 条件が満たされるまで待つ。時間切れになったら false を返す。
    ///
    /// 到着そのもの (結果が確定する・器が 1 枚増える) のように、一度成り立てば覆らない条件に使う。
    /// 遷移の途中に終端と見分けのつかない一瞬がある観測は [awaitSettled] で待つ。
    @MainActor
    static func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: pollingInterval)
        }
        return condition()
    }

    /// 落ち着き待ちの 1 回の観測。
    struct Reading {
        /// 目的の終端状態に達しているか。
        ///
        /// 独立した複数の観測の合意と、遷移を動かしている演出が走っていないことを、
        /// 呼び出し側がここで組み立てる (何が独立かは面ごとに違うため)。
        let settled: Bool

        /// その時点の観測を 1 行で表した文字列。変化した時点だけが履歴に残る。
        let state: String

        init(settled: Bool, _ state: String) {
            self.settled = settled
            self.state = state
        }
    }

    /// 落ち着き待ちの結果。
    struct Outcome {
        /// 落ち着いたか (時間切れなら false)。
        let settled: Bool

        private let history: DialogTestStateHistory

        init(settled: Bool, history: DialogTestStateHistory) {
            self.settled = settled
            self.history = history
        }

        /// 時間切れの説明文。何を待っていたかと、観測できていた履歴を添える。
        @MainActor
        func message(_ reason: String) -> Comment {
            Comment(
                rawValue: """
                    \(reason)
                    観測履歴 (数値は観測開始からの経過ミリ秒):
                    \(history.format())
                    """
            )
        }
    }

    /// 観測が [stable] の間続けて落ち着いたと読めるまで待つ。
    ///
    /// 遷移の途中には、目的の終端状態と見分けのつかない一瞬が現れる — 器が 1 枚増えた時点が
    /// 「増えて終わり」とも「これから入れ替わる途中」とも読める窓。その一瞬を読んで先へ進むと、
    /// 後の検査が途中の並びを終端として固定してしまう。ここでは 1 回の読みで判定せず、
    /// 観測が続けて成り立つことを求める。途中で 1 度でも崩れたら、そこから数え直す。
    ///
    /// 時間切れになった回に何が起きていたかは事後には読めないので、観測が変わるたびに履歴へ積み、
    /// [Outcome.message] で失敗の説明文に添える。
    @MainActor
    static func awaitSettled(
        timeout: Duration = .seconds(5),
        stable: Duration = defaultStable,
        _ read: @MainActor () -> Reading
    ) async -> Outcome {
        let history = DialogTestStateHistory()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var heldSince: ContinuousClock.Instant?
        while true {
            let now = ContinuousClock.now
            let reading = read()
            history.recordChange(reading.state)
            if reading.settled {
                let since = heldSince ?? now
                heldSince = since
                if since.duration(to: now) >= stable {
                    return Outcome(settled: true, history: history)
                }
            } else {
                heldSince = nil
            }
            if now >= deadline {
                return Outcome(settled: false, history: history)
            }
            try? await Task.sleep(for: pollingInterval)
        }
    }
}

/// 単調時計付きの観測履歴。時間切れになった回に何が起きていたかを説明文へ添えるために使う。
///
/// 事後には読めない経過 (要求の順序・器の出入り・見えの遷移) を、起きた時点で積む。
/// 上限に達したら**中ほどを捨てて先頭と末尾を残す** — 読みたいのは始まりの経緯と時間切れの直前で、
/// 履歴が上限に届くのは状態が細かく振れている回、つまり最も読みたい回だから。
@MainActor
final class DialogTestStateHistory {

    /// 始まりの経緯として残す件数。
    private static let defaultHeadLimit = 100

    /// 時間切れの直前として残す件数。
    private static let defaultTailLimit = 400

    private let headLimit: Int
    private let tailLimit: Int
    private let startedAt = ContinuousClock.now
    private var head: [String] = []
    private var tail: [String] = []
    private var dropped = 0

    /// 直前に積んだ状態の文字列。同じ状態が続く間は積まない。
    private var lastState: String?

    init(headLimit: Int = defaultHeadLimit, tailLimit: Int = defaultTailLimit) {
        self.headLimit = headLimit
        self.tailLimit = tailLimit
    }

    /// 出来事を単調時計付きで積む。
    func record(_ label: String) {
        let elapsed = startedAt.duration(to: .now).components
        let millis = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
        let line = "+\(millis)ms \(label)"
        if head.count < headLimit {
            head.append(line)
            return
        }
        tail.append(line)
        while tail.count > tailLimit {
            tail.removeFirst()
            dropped += 1
        }
    }

    /// 状態を積む。直前と同じ内容なら積まない (変化した時点だけが履歴に残る)。
    func recordChange(_ state: String) {
        if state == lastState { return }
        lastState = state
        record(state)
    }

    /// 積んだ履歴を古い順に並べた本文。捨てた区間があればその旨を挟む。
    func format() -> String {
        var lines = head
        if dropped > 0 {
            lines.append("(履歴の中ほど \(dropped) 件は上限のため捨てた)")
        }
        lines.append(contentsOf: tail)
        return lines.joined(separator: "\n")
    }
}
#endif
