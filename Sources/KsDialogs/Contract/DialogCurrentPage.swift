#if canImport(UIKit)
import UIKit

/// 基準領域 `DialogLayoutArea.currentPage` が使う「表示中のページ」をアプリから教える口。
///
/// 既定では、ライブラリがウィンドウの view controller を辿って表示中のページを見つける
/// (present された画面・`UINavigationController` の先頭・`UITabBarController` の選択中のタブ)。
/// 独自のコンテナで画面を切り替えているなど、その辿り方で届かないアプリは、
/// 表示中のページの View を返す関数をここに一度登録する。SwiftUI の画面では
/// View に `markAsDialogCurrentPage()` を付ける方法を使う。
///
/// 登録した関数は各表示の開始時と、表示中にウィンドウの寸法や safe area が変わったときに呼ばれる。
/// 登録の差し替えは次の表示から効き、表示中のダイアログには影響しない。
@MainActor
public enum DialogCurrentPage {
    /// 表示中のページの View を返す関数。`nil` を代入すると既定の探し方に戻る。
    ///
    /// 関数が `nil` を返したとき・エラーを投げたとき・返した View がダイアログを出すウィンドウに
    /// 載っていないとき・safe area の内側が空のとき・その内側がウィンドウの外にあるときは、
    /// 既定の探し方で得たページを使う。
    /// 基準になるのは返した View の safe area の内側 (`safeAreaLayoutGuide.layoutFrame`)。
    public static var provider: (@MainActor () throws -> UIView?)?
}
#endif
