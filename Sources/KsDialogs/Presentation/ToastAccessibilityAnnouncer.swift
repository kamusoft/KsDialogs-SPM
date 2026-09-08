#if canImport(UIKit)
import UIKit

/// 支援技術 (VoiceOver) への通知口。
///
/// デフォルト View の Toast は表示時にメッセージを読み上げへ流すが、
/// フォーカスは移動させない。フォーカスを動かす通知 (`.screenChanged` / `.layoutChanged`) を
/// 使わないことがその保証であり、この面を差し替えると発行した通知の種類まで観察できる。
protocol ToastAccessibilityAnnouncer: Sendable {
    /// 通知を1件発行する。
    @MainActor func post(notification: UIAccessibility.Notification, argument: Any?)
}

/// OS の支援技術へそのまま流す既定の通知口。
struct SystemToastAccessibilityAnnouncer: ToastAccessibilityAnnouncer {
    @MainActor
    func post(notification: UIAccessibility.Notification, argument: Any?) {
        UIAccessibility.post(notification: notification, argument: argument)
    }
}
#endif
