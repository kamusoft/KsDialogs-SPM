#if canImport(UIKit)
/// 利用者のコード (factory・configure など) が呼ばれた回数を数える。
@MainActor
final class DialogTestCallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
#endif
