#if canImport(UIKit)
import SwiftUI

public extension View {
    /// この View を、基準領域 `DialogLayoutArea.currentPage` が使う「表示中のページ」として名乗らせる。
    ///
    /// `TabView` や `NavigationStack` で組んだ画面では、各画面の中身の枠 (バーの内側) に 1 回付ける。
    /// 付けた View が画面に配置されている間だけ候補になり、画面から外れると候補から外れる。
    /// 候補が複数あるときは次の順で 1 つに決まる。
    ///
    /// - ダイアログを出すウィンドウと別のウィンドウにあるもの、ウィンドウの外に置かれたものは使わない
    /// - 画面に表示されていないもの (非表示の祖先や不透明度 0 の祖先を持つもの。
    ///   `TabView` の切り替えの演出中に残っている去るタブの画面など) は使わない
    /// - 候補が入れ子になっていれば内側の View を使う
    /// - それ以外は最後に画面へ配置された View を使う
    ///
    /// 基準になるのは付けた View の矩形のうち safe area の内側。候補が無いときは
    /// `DialogCurrentPage.provider` に登録した関数、それも無ければ既定の探し方で得たページを使う。
    func markAsDialogCurrentPage() -> some View {
        background(DialogCurrentPageMarker())
    }
}
#endif
