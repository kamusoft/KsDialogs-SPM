#if canImport(UIKit)
/// Loading の状態の正が残した警告を、残した順に書き留める。
@MainActor
final class LoadingTestWarningRecorder {
    private(set) var messages: [String] = []

    func record(_ message: String) {
        messages.append(message)
    }
}
#endif
