/// 結果の型消去表現。
/// 公開 API の `DialogResult` と違い結果値の型を持たず、レジストリ・提示層・互換面が共通に使う輸送形。
/// 値の実体は報告側が生成したものをそのまま運ぶだけなので、並行性の検査は輸送箱として外している。
enum DialogOutcome: @unchecked Sendable {
    case completed(Any)
    case cancelled
}
