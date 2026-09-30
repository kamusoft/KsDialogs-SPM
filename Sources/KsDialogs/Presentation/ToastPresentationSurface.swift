#if canImport(UIKit)
import UIKit

/// Toast の器を取り付ける面を供給する。
///
/// Toast は OS の提示スタックに載せず、取り付け先の View へ直接重ねる (core/ADR-0030)。
/// 取り付け先はライブラリが自動解決するため、表示の呼び出し側はこの面に関与しない。
protocol ToastPresentationSurface: Sendable {
    /// Toast の器を重ねる先。取り付け先が無ければ nil (表示は保留され、提示先の出現を待つ)。
    @MainActor var hostView: UIView? { get }

    /// アプリが前面にいるか。
    ///
    /// 前面にいるのに取り付け先が無い間 (起動の途中・割り込みの最中) に表示を始めた Toast は、
    /// 期限を決めずに待ち、取り付けた時点から表示時間を数える (core/ADR-0043)。
    @MainActor var isAppInForeground: Bool { get }

    /// 提示先が現れたかもしれないことの合図を購読する。
    ///
    /// 機能はこの口のほかに提示先の出現を知る手段を持たない。合図を受けたら提示先を読み直し、
    /// 現れていなければ待ち続ける。待っている表示が無くなったら購読を解除する。
    @MainActor func observeHostAppearance(
        _ handler: @escaping DialogHostAppearanceHandler
    ) -> DialogHostAppearanceRegistration

    /// アプリが前面を離れた合図を購読する。
    ///
    /// 期限を決めずに待っている表示が、取り付け先に載らないまま背面へ下がった時点から数え始めるために使う。
    /// そうした表示が無くなったら購読を解除する。
    @MainActor func observeForegroundDeparture(
        _ handler: @escaping DialogForegroundDepartureHandler
    ) -> DialogHostAppearanceRegistration
}

/// key window そのものを取り付け先にする既定の面。
///
/// window の直下に重ねるため、Toast の表示は画面遷移をまたいで継続する。
final class KeyWindowToastPresentationSurface: ToastPresentationSurface {
    private let keyWindowProvider: any DialogKeyWindowProvider

    init(keyWindowProvider: any DialogKeyWindowProvider = ApplicationKeyWindowProvider()) {
        self.keyWindowProvider = keyWindowProvider
    }

    @MainActor
    var hostView: UIView? {
        keyWindowProvider.keyWindow
    }

    @MainActor
    var isAppInForeground: Bool {
        keyWindowProvider.isAppInForeground
    }

    @MainActor
    func observeHostAppearance(
        _ handler: @escaping DialogHostAppearanceHandler
    ) -> DialogHostAppearanceRegistration {
        keyWindowProvider.observeHostAppearance(handler)
    }

    @MainActor
    func observeForegroundDeparture(
        _ handler: @escaping DialogForegroundDepartureHandler
    ) -> DialogHostAppearanceRegistration {
        keyWindowProvider.observeForegroundDeparture(handler)
    }
}
#endif
