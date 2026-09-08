/// 器が辿る状態。閉鎖信号の扱いはこの状態で決まる。
///
/// - `created`: show の呼び出しで器を組み立てた直後。まだ画面に載っていない
/// - `attached`: 器を画面に載せてレイアウトを走らせ、実効値を固定した時点。中身はまだ見えない
/// - `presenting`: 覆いのフェードと出現の演出を進めている間
/// - `shown`: 利用者の操作と結果報告を受け付ける
/// - `dismissing`: 退出の演出と覆いのフェードを進めている間。入力は受け付けない
/// - `removed`: 器を撤去し、確定済みの結果を呼び出し元へ配送した後
enum DialogContainerState: Sendable {
    case created
    case attached
    case presenting
    case shown
    case dismissing
    case removed
}
