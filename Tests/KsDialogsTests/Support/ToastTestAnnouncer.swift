#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// 支援技術への通知を書き留める観測用の通知口。
/// 発行された通知の種類まで残すので、フォーカスを動かす通知が混じっていないかを見られる。
@MainActor
final class ToastTestAnnouncer: ToastAccessibilityAnnouncer {
    /// 発行された1件分。
    struct Post {
        let notification: UIAccessibility.Notification
        let argument: Any?
    }

    private(set) var posts: [Post] = []

    nonisolated init() {}

    func post(notification: UIAccessibility.Notification, argument: Any?) {
        posts.append(Post(notification: notification, argument: argument))
    }

    /// 読み上げへ流された文言。並びは発行順。
    var announcedMessages: [String] {
        posts.filter { $0.notification == .announcement }.compactMap { $0.argument as? String }
    }

    /// 支援技術のフォーカスを移動させる通知が発行されたか。
    var didMoveFocus: Bool {
        posts.contains { $0.notification == .screenChanged || $0.notification == .layoutChanged }
    }
}
#endif
