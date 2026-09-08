/// 結果が確定した原因。公開 API には出さず、提示層が退出の進め方を決めるためだけに使う。
///
/// 「どの操作でキャンセルされたか」を利用者へ返さない結果通知のルールは変わらない。
/// 戻るボタンは Android 系統だけの閉鎖経路なので、この面には現れない。
enum DialogDismissalOrigin: Sendable {
    /// 中身からの結果報告。
    case report
    /// 覆いへのタップ。
    case outsideTap
    /// show を待っている呼び出し元の取り消し。
    case callerCancellation
    /// 器が画面を失ったこと (画面破棄・提示関係の外部からの解除)。
    /// この原因では器が演出できないため、退出の演出は行わない。
    case hostLost
}
