/// ダイアログ側から結果を報告する部品。
/// 完了 (結果値つき) とキャンセルの2操作のみを持ち、結果値の型は ViewModel の宣言に固定される。
///
/// 報告はちょうど1回だけ有効で、確定後の報告は何も起こさない (core/ADR-0003)。
/// 任意のスレッドから呼び出してよい。
public final class DialogNotifier<Result: Sendable>: Sendable {
    private let resultChannel: DialogResultChannel

    init(resultChannel: DialogResultChannel) {
        self.resultChannel = resultChannel
    }

    /// 結果値つきで完了を報告する。
    public func complete(_ value: Result) {
        resultChannel.settle(.completed(value))
    }

    /// キャンセルを報告する。
    public func cancel() {
        resultChannel.settle(.cancelled)
    }
}
