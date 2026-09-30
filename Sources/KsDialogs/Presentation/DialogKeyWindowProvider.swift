#if canImport(UIKit)
import UIKit

/// ダイアログの提示起点となる window を供給する。
/// アプリの window 取得手段を差し替えられるようにするための内部の継ぎ目。
///
/// 提示先を選ぶ規則 (`keyWindow`) と、提示先が現れたかもしれないことの合図
/// (`observeHostAppearance`) を同じ供給元に置く。規則を変えるときに、合図の見る通知も
/// 一緒に見直せるようにするため。アプリが前面にいるかの判定 (`isAppInForeground`) と
/// 前面を離れた合図 (`observeForegroundDeparture`) も、同じシーンの状態から作るのでここに置く
/// (提示先の判定と前面の判定が食い違わないようにする — core/ADR-0043)。
protocol DialogKeyWindowProvider: Sendable {
    @MainActor var keyWindow: UIWindow? { get }

    /// アプリが前面にいるか。前面 (アクティブでなくてもよい) のシーンが 1 つ以上あれば前面とする。
    ///
    /// 前面にいるのに提示先が無い間 (起動の途中・割り込みの最中) は「前面の待ち」になる。
    @MainActor var isAppInForeground: Bool { get }

    /// 提示先が現れたかもしれないことの合図を購読する。
    ///
    /// 合図は「現れたかもしれない」ことだけを知らせる。受け取った側は `keyWindow` を読み直して、
    /// 表示するか待ち続けるかを決める。合図の順序や回数に意味を持たせない。
    /// - Parameter handler: 合図のたびに UI スレッドで呼ばれる
    /// - Returns: 購読1件。解除するまで合図が届き続ける
    @MainActor func observeHostAppearance(
        _ handler: @escaping DialogHostAppearanceHandler
    ) -> DialogHostAppearanceRegistration

    /// アプリが前面を離れた (前面のシーンが 1 つも無くなった) 合図を購読する。
    ///
    /// 提示先の出現の合図とは別の口にする。前面の待ちで期限を決めずに待っている表示が、
    /// 背面へ下がった時点から数え始めるために使う。
    /// - Parameter handler: 合図のたびに UI スレッドで呼ばれる
    /// - Returns: 購読1件。解除するまで合図が届き続ける
    @MainActor func observeForegroundDeparture(
        _ handler: @escaping DialogForegroundDepartureHandler
    ) -> DialogHostAppearanceRegistration
}
#endif
