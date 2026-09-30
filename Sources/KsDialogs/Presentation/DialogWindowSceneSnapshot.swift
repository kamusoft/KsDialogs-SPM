#if canImport(UIKit)
import UIKit

/// 提示起点の選択と前面の判定に使う、シーン1つ分の情報。
struct DialogWindowSceneSnapshot {
    /// そのシーンの活動状態。
    let activationState: UIScene.ActivationState
    /// そのシーンが持つ window。
    let windows: [UIWindow]

    /// そのシーンが前面でアクティブか。提示先はこの状態のシーンからだけ選ぶ。
    var isForegroundActive: Bool {
        activationState == .foregroundActive
    }

    /// そのシーンが前面にいるか (アクティブでなくてもよい)。
    ///
    /// 起動の途中や割り込み (システムの許可ダイアログなど) の最中のシーンは foregroundInactive で、
    /// 利用者の目の前にはあるが提示先にはならない。この間を背面と区別するために使う (core/ADR-0043)。
    var isForeground: Bool {
        activationState == .foregroundActive || activationState == .foregroundInactive
    }
}
#endif
