#if canImport(UIKit)
import Foundation

@testable import KsDialogs

/// ObjC 互換面へ渡すクロージャの呼び出しを記録する。
/// 互換面の呼び出し元は特定の隔離を前提にできないため、ロックで保護する。
final class DialogInteropTestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var notifiers: [KsDialogsInteropNotifier] = []
    private var results: [KsDialogsInteropResult] = []

    func record(notifier: KsDialogsInteropNotifier) {
        lock.lock()
        defer { lock.unlock() }
        notifiers.append(notifier)
    }

    func record(result: KsDialogsInteropResult) {
        lock.lock()
        defer { lock.unlock() }
        results.append(result)
    }

    var notifierCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return notifiers.count
    }

    var resultCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return results.count
    }

    func notifier(at index: Int) -> KsDialogsInteropNotifier? {
        lock.lock()
        defer { lock.unlock() }
        return index < notifiers.count ? notifiers[index] : nil
    }

    var firstResult: KsDialogsInteropResult? {
        lock.lock()
        defer { lock.unlock() }
        return results.first
    }
}
#endif
