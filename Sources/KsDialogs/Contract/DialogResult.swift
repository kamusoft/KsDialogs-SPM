/// ダイアログの結果。
/// 完了 (結果値つき) とキャンセル (結果値なし) を型で区別する (core/ADR-0003)。
public enum DialogResult<Value: Sendable>: Sendable {
    /// ダイアログ側の完了操作で確定した結果。
    case completed(Value)
    /// キャンセル操作・外側タップで確定した結果。結果値は持たない。
    case cancelled
}

extension DialogResult: Equatable where Value: Equatable {}
