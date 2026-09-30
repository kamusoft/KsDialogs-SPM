/// サイズと位置の計算を行う基準領域。
///
/// 水平・垂直の両軸に効く (core/ADR-0008)。
public enum DialogLayoutArea: Sendable, Equatable {
    /// ダイアログを載せるウィンドウの全体。
    case window

    /// ウィンドウからシステムバーなどが占める余白 (safe area) を控除した可視領域。
    case visibleArea

    /// 表示中のページの矩形のうち、そのページ自身の safe area の内側。
    ///
    /// タブバーやナビゲーションバーを持つ画面では、それらのバーを除いた領域が基準になる。
    /// 表示中のページは次の順で探し、見つかった最初のものを使う。
    ///
    /// 1. SwiftUI の `markAsDialogCurrentPage()` を付けた View のうち、画面に配置されているもの
    /// 2. `DialogCurrentPage.provider` に登録した関数が返す View
    /// 3. ライブラリが内蔵する既定の探し方 (ウィンドウの view controller を、present された画面・
    ///    `UINavigationController` の先頭・`UITabBarController` の選択中のタブと先端まで辿った先の view)
    ///
    /// どれからもページが得られないときは `visibleArea` と同じ結果になる。
    case currentPage
}
