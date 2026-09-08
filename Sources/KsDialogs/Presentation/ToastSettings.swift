#if canImport(UIKit)
import Foundation

/// Toast の設定プロパティ (`ToastStyle`) の置き場。
///
/// 設定は任意のスレッドから読み書きでき、器は各表示の受理時にここから読む
/// (core/ADR-0032 の「設定変更は次の表示から効く」)。
final class ToastSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStyle = ToastStyle()

    /// Toast の一括設定。
    var style: ToastStyle {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedStyle
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedStyle = newValue
        }
    }
}
#endif
