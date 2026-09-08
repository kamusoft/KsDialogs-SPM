#if canImport(UIKit)
import UIKit

/// Loading の器を取り付ける面を供給する。
///
/// Loading は Dialog 機構の提示スタックに載せず、取り付け先の View へ直接重ねる (core/ADR-0022)。
/// 取り付け先はライブラリが自動解決するため、表示の呼び出し側はこの面に関与しない。
protocol LoadingPresentationSurface: Sendable {
    /// Loading の器を重ねる先。取り付け先が無ければ nil (表示は成立しないが処理は実行される)。
    @MainActor var hostView: UIView? { get }
}

/// key window そのものを取り付け先にする既定の面。
///
/// window の直下に重ねるため、提示中のダイアログ (present の連なり) より手前に載る。
final class KeyWindowLoadingPresentationSurface: LoadingPresentationSurface {
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
