#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// Toast の取り付け先と、アプリが前面にいるかをテストが差し替える面。
///
/// 実装との対応は次のとおり:
///
/// - `hostView` は前面でアクティブなシーンの key window に対応する。nil にすると提示環境が無い状況を再現できる
/// - `isAppInForeground` は供給元の前面の判定に対応する。取り付け先が無く前面にいる状態が「前面の待ち」、
///   取り付け先が無く前面にいない状態が「背面」になる
/// - `fireHostAppearance()` は提示先の出現の合図 (window の key 化・シーンのアクティブ化) に対応する
/// - `leaveForeground()` は最後の前面のシーンが背面へ入ったこと (前面を離れた合図) に対応する
@MainActor
final class ToastTestPresentationSurface: ToastPresentationSurface {
    var hostView: UIView?

    var isAppInForeground: Bool

    /// - Parameters:
    ///   - hostView: 最初の取り付け先
    ///   - isAppInForeground: 最初の前面の判定。取り付け先が無いまま前面の待ちか背面かを選ぶ
    init(hostView: UIView?, isAppInForeground: Bool = true) {
        self.hostView = hostView
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

    /// 取り付け先を戻し、提示先の出現の合図を送る。
    ///
    /// 取り付け先があるのは前面にいる間だけなので、前面の判定も前面に戻す。
    func returnHost(_ view: UIView) {
        hostView = view
        isAppInForeground = true
        hostAppearance.fire()
    }

    /// 取り付け先を失ったまま背面へ下がったことを起こし、前面を離れた合図を送る。
    func leaveForeground() {
        hostView = nil
        isAppInForeground = false
        foregroundDeparture.fire()
    }
}
#endif
