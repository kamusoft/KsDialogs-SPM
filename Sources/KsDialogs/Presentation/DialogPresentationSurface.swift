#if canImport(UIKit)
import CoreGraphics

/// 器が画面から外れ終わったことを知らせる口。
typealias DialogRemovalCompletion = @MainActor () -> Void

/// ダイアログの器を画面へ出し入れする面。
/// 提示先はライブラリが自動解決するため、show の呼び出し側はこの面に関与しない。
protocol DialogPresentationSurface: Sendable {
    /// 今ダイアログを提示できるか (アクティブな提示先が存在するか)。
    @MainActor var canPresent: Bool { get }

    /// 提示したときに器が占める矩形。提示前にサイズを確定させるために使う。
    @MainActor var presentationBounds: CGRect { get }

    /// 器を最前面へ提示する。
    @MainActor func present(_ container: DialogContainerViewController)

    /// その器だけを閉じる。提示関係の解消と View の取り外しまで終わったら `completion` を呼ぶ。
    /// 既に画面から外れている器に対しては、待つ相手がいないのでその場で `completion` を呼ぶ。
    @MainActor func dismiss(
        _ container: DialogContainerViewController,
        completion: @escaping DialogRemovalCompletion
    )
}
#endif
