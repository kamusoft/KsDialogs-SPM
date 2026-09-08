#if canImport(UIKit)
import Foundation

/// Loading の設定プロパティ (スタイルと既定ローディングの器メタ属性) の置き場。
///
/// 設定は任意のスレッドから読み書きでき、器は各表示の開始時にここから読む
/// (core/ADR-0023 の「設定変更は次の表示から効く」)。
final class LoadingSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStyle = LoadingStyle()
    private var storedOptions = DialogOptions()

    /// 既定ローディングの見た目。
    var style: LoadingStyle {
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

    /// 既定ローディングの器メタ属性。
    var options: DialogOptions {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOptions
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedOptions = newValue
        }
    }
}
#endif
