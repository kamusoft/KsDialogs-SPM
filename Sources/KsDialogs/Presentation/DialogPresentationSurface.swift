#if canImport(UIKit)
import CoreGraphics

/// 器が画面から外れ終わったことを知らせる口。
typealias DialogRemovalCompletion = @MainActor () -> Void

/// 器の提示が終わったことを知らせる口。
/// 引数は器を画面へ載せられたか。載せられなかった (提示先が無い・提示機構が受け付けない) ときは false。
typealias DialogPresentationCompletion = @MainActor (_ didPresent: Bool) -> Void

/// ダイアログの器を画面へ出し入れする面。
/// 提示先はライブラリが自動解決するため、show の呼び出し側はこの面に関与しない。
protocol DialogPresentationSurface: Sendable {
    /// 今ダイアログを提示できるか (アクティブな提示先が存在するか)。
    @MainActor var canPresent: Bool { get }

    /// 提示したときに器が占める矩形。提示前にサイズを確定させるために使う。
    @MainActor var presentationBounds: CGRect { get }

    /// 提示先の出現を待つ show が並ぶ列。同じ提示先を共有する面は同じ列を返す。
    /// 呼び出しの時点で順番札を取れるよう、任意のスレッドから読める。
    var hostWaitQueue: DialogHostWaitQueue { get }

    /// 器を最前面へ提示する。提示機構が提示を終えたら `completion(true)` を呼ぶ。
    /// 器を載せられなかったときは、器を提示の連なりに残さずに `completion(false)` を呼ぶ。
    /// どちらの場合も `completion` はちょうど 1 回呼ぶ。提示先を待っていた次の show は、この完了のあとに明ける。
    @MainActor func present(
        _ container: DialogContainerViewController,
        completion: @escaping DialogPresentationCompletion
    )

    /// その器だけを閉じる。提示関係の解消と View の取り外しまで終わったら `completion` を呼ぶ。
    /// 既に画面から外れている器に対しては、待つ相手がいないのでその場で `completion` を呼ぶ。
    @MainActor func dismiss(
        _ container: DialogContainerViewController,
        completion: @escaping DialogRemovalCompletion
    )

    /// 提示先が現れたかもしれないことの合図を購読する。
    ///
    /// 機能はこの口のほかに提示先の出現を知る手段を持たない。合図を受けたら提示先を読み直し、
    /// 現れていなければ待ち続ける。待っている表示が無くなったら購読を解除する。
    @MainActor func observeHostAppearance(
        _ handler: @escaping DialogHostAppearanceHandler
    ) -> DialogHostAppearanceRegistration
}
#endif
