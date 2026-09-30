#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// テストが用意した window を提示起点として供給する。
/// window を持たない状態にすると「提示先が存在しない」状況を再現できる。
///
/// 前面の判定と前面を離れた合図も手で操作できる。提示先が無く前面にいる状態が「前面の待ち」、
/// 提示先が無く前面にいない状態が「背面」になる。
@MainActor
final class DialogTestKeyWindowProvider: DialogKeyWindowProvider {
    var keyWindow: UIWindow?

    /// アプリが前面にいるか (本番の、前面のシーンが 1 つ以上あるかに対応する)。
    var isAppInForeground: Bool

    init(keyWindow: UIWindow?, isAppInForeground: Bool = true) {
        self.keyWindow = keyWindow
        self.isAppInForeground = isAppInForeground
    }

    /// 提示先の出現の合図の発火口。`fireHostAppearance()` で合図を送る。
    let hostAppearance = DialogTestHostAppearanceSignal()

    /// 前面を離れた合図の発火口。`leaveForeground()` で合図を送る。
    let foregroundDeparture = DialogTestHostAppearanceSignal()

    func observeHostAppearance(
        _ handler: @escaping DialogHostAppearanceHandler
    ) -> DialogHostAppearanceRegistration {
        hostAppearance.observe(handler)
    }

    func observeForegroundDeparture(
        _ handler: @escaping DialogForegroundDepartureHandler
    ) -> DialogHostAppearanceRegistration {
        foregroundDeparture.observe(handler)
    }

    /// 提示先の出現の合図を送る (本番の window の key 化・シーンのアクティブ化に対応する)。
    func fireHostAppearance() {
        hostAppearance.fire()
    }

    /// 提示先を失ったまま背面へ下がったことを起こし、前面を離れた合図を送る
    /// (本番の、最後の前面のシーンが背面へ入った通知に対応する)。
    func leaveForeground() {
        keyWindow = nil
        isAppInForeground = false
        foregroundDeparture.fire()
    }
}
#endif
