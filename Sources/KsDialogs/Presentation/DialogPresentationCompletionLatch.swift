#if canImport(UIKit)
/// 提示の完了通知を 1 回だけ通す口。
///
/// 提示機構の完了通知と、提示面が自分で下す「載せられなかった」の判定が、同じ 1 回の提示で
/// 両方届くことがないようにする。先に届いた方だけを `completion` へ流す。
@MainActor
final class DialogPresentationCompletionLatch {
    private var completion: DialogPresentationCompletion?

    /// 載せられなかった (`false`) と知らせ済みか。
    private(set) var hasReportedFailure = false

    init(_ completion: @escaping DialogPresentationCompletion) {
        self.completion = completion
    }

    /// まだ知らせていなければ `didPresent` を知らせる。2 回目以降は何もしない。
    func report(_ didPresent: Bool) {
        guard let completion else { return }
        self.completion = nil
        hasReportedFailure = !didPresent
        completion(didPresent)
    }
}
#endif
