import Foundation

/// 実行中のスレッドを観察する補助。
/// 非同期文脈から直接 `Thread.isMainThread` を読めないため、同期関数として切り出す。
enum DialogTestThread {
    static func isMainThread() -> Bool {
        Thread.isMainThread
    }
}
