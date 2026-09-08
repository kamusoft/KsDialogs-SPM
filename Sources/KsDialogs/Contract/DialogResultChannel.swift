import Foundation

/// 1回の show に対応する結果チャネル。
/// 任意のスレッドからの報告を受け付け、最初の報告だけを有効として下流へ流す (2回目以降は捨てる)。
/// この最初の1回で結果が不可逆に確定する (ラッチ) 一方、呼び出し元への配送は
/// 器の撤去まで進んだ提示層が別に行う。
///
/// 受け取り側 (提示層) のハンドラ登録より先に報告が来る場合があるため、
/// ハンドラ未登録のうちに確定した結果は保持しておき、登録時にそのまま引き渡す。
final class DialogResultChannel: @unchecked Sendable {
    private let lock = NSLock()
    private var isSettled = false
    private var settledOrigin: DialogDismissalOrigin?
    private var latchedOutcome: DialogOutcome?
    private var pendingOutcome: DialogOutcome?
    private var handler: (@Sendable (DialogOutcome) -> Void)?
    private var callerCancellationHandler: (@Sendable () -> Void)?

    /// 結果を確定させる。確定済みなら何もしない。
    /// - Parameters:
    ///   - outcome: 確定させる結果
    ///   - origin: その結果を確定させた原因。提示層が退出の進め方を決めるために読む
    func settle(_ outcome: DialogOutcome, origin: DialogDismissalOrigin = .report) {
        lock.lock()
        guard !isSettled else {
            lock.unlock()
            return
        }
        isSettled = true
        settledOrigin = origin
        latchedOutcome = outcome
        if let handler {
            self.handler = nil
            lock.unlock()
            handler(outcome)
        } else {
            pendingOutcome = outcome
            lock.unlock()
        }
    }

    /// 結果確定時に一度だけ呼ばれるハンドラを登録する。登録時点で確定済みなら即座に呼ぶ。
    func onSettle(_ handler: @escaping @Sendable (DialogOutcome) -> Void) {
        lock.lock()
        if let outcome = pendingOutcome {
            pendingOutcome = nil
            lock.unlock()
            handler(outcome)
        } else {
            self.handler = handler
            lock.unlock()
        }
    }

    /// 結果が確定済みかどうか。
    var isResultSettled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isSettled
    }

    /// 結果を確定させた原因。未確定なら nil。
    var resultOrigin: DialogDismissalOrigin? {
        lock.lock()
        defer { lock.unlock() }
        return settledOrigin
    }

    /// 確定した結果。未確定なら nil。ハンドラの登録状況とは無関係にいつでも読める。
    var settledOutcome: DialogOutcome? {
        lock.lock()
        defer { lock.unlock() }
        return latchedOutcome
    }

    /// 呼び出し元の取り消しを知らせる。
    ///
    /// 未確定ならキャンセルとして確定させたうえで、確定済みかどうかによらず観察者へ伝える。
    /// 確定済みでも伝えるのは、退出の途中でも呼び出し元が待つのをやめられるようにするため。
    func cancelFromCaller() {
        settle(.cancelled, origin: .callerCancellation)
        lock.lock()
        let observer = callerCancellationHandler
        lock.unlock()
        observer?()
    }

    /// 呼び出し元の取り消しを観察するハンドラを登録する。
    func onCallerCancellation(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        callerCancellationHandler = handler
        lock.unlock()
    }
}
