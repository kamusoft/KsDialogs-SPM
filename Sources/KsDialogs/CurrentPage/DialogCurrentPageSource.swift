#if canImport(UIKit)
import UIKit

/// 表示中のページの基準矩形を、提示先ウィンドウの座標で返す取得元。
///
/// 利用者に見せる登録口 (SwiftUI の modifier・View を返す関数・内蔵の既定の探し方) は
/// すべてこの形へ揃えてから問い合わせる。矩形を直接返す形は公開しない (core/ADR-0038)。
@MainActor
protocol DialogCurrentPageSource {
    /// ダイアログを出すウィンドウに属するページを探す。
    /// 別のウィンドウに属するもの・ウィンドウと重ならないもの・空の矩形は見つからなかった扱いにする。
    func lookUpPageRect(in window: UIWindow) -> DialogCurrentPageLookup
}
#endif
