#if canImport(UIKit)
import UIKit

/// Toast の器を取り付ける面を供給する。
///
/// Toast は OS の提示スタックに載せず、取り付け先の View へ直接重ねる (core/ADR-0030)。
/// 取り付け先はライブラリが自動解決するため、表示の呼び出し側はこの面に関与しない。
protocol ToastPresentationSurface: Sendable {
    /// Toast の器を重ねる先。取り付け先が無ければ nil (表示は保留され、提示先の出現を待つ)。
    @MainActor var hostView: UIView? { get }
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
}
#endif
