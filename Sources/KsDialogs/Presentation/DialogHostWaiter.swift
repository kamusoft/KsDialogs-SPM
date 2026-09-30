#if canImport(UIKit)
/// 提示先を待つ列に並んでいる show 1 件。
@MainActor
final class DialogHostWaiter {
    /// この show が提示に使う面。明けてよいかは、この面の提示先を読み直して決める。
    let surface: any DialogPresentationSurface

    /// 列の順番札。列は札の小さい順に並ぶ。
    let ticket: UInt64

    private var continuation: CheckedContinuation<DialogHostWaitTurn, Never>?

    init(surface: any DialogPresentationSurface, ticket: UInt64) {
        self.surface = surface
        self.ticket = ticket
    }

    /// 待ちを再開させる口を控える。
    func attach(_ continuation: CheckedContinuation<DialogHostWaitTurn, Never>) {
        self.continuation = continuation
    }

    /// 待ちを明ける。1 回だけ効き、2 回目以降は何もしない。
    func resume(_ turn: DialogHostWaitTurn) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: turn)
    }
}
#endif
