#if canImport(UIKit)
import UIKit

/// 閉鎖の依頼を書き留める提示元。
///
/// 提示遷移はテスト実行環境 (シーンを持たないテストランナー) では完走せず、UIKit からの完了通知も
/// 届かない。提示元として渡された `dismiss(animated:completion:)` をここで受け止めることで、
/// 「提示元へアニメーションなしの閉鎖を依頼し、その完了通知を撤去完了として流す」結線だけを観察できる。
@MainActor
final class RecordingPresentingViewController: UIViewController {
    /// 受け取った閉鎖依頼のアニメーション指定 (受け取った順)。
    private(set) var dismissalRequests: [Bool] = []

    /// 依頼を書き留め、提示機構が撤去を終えたときと同じように完了を知らせる。
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissalRequests.append(flag)
        completion?()
    }
}
#endif
