#if canImport(UIKit)
@testable import KsDialogs

/// テスト用の提示面・供給元が持つ、合図 (提示先の出現・前面を離れたこと) の発火口。
///
/// 本番の供給元は OS の通知から合図を作るが、テストでは `fire()` で任意の時点に合図を送る。
/// 購読の数を数えるので、待つ理由の無くなったときに購読が解除されたかも観察できる。
@MainActor
final class DialogTestHostAppearanceSignal {
    private var handlers: [Int: DialogHostAppearanceHandler] = [:]
    private var nextID = 0

    /// 解除されていない購読の数。
    var activeRegistrationCount: Int {
        handlers.count
    }

    /// これまでに受け付けた購読の総数 (解除済みを含む)。
    private(set) var totalRegistrationCount = 0

    func observe(_ handler: @escaping DialogHostAppearanceHandler) -> DialogHostAppearanceRegistration {
        let id = nextID
        nextID += 1
        totalRegistrationCount += 1
        handlers[id] = handler
        return DialogHostAppearanceRegistration { [weak self] in
            self?.handlers[id] = nil
        }
    }

    /// 購読中のすべての口へ合図を送る。購読した順に届ける。
    func fire() {
        for id in handlers.keys.sorted() {
            // 合図を受けた側が購読を解除することがあるので、届ける直前に残っているかを確かめる。
            handlers[id]?()
        }
    }
}
#endif
