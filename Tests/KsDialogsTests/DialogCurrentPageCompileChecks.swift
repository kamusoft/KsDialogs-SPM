#if canImport(UIKit)
import SwiftUI
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// 基準領域「表示中のページ」の公開 API 形状のコンパイル検証。
///
/// 基準領域の値・ページの View を返す関数の登録と解除・SwiftUI の modifier を、
/// 型注釈を足さずに利用者と同じ形で書けることを既定のビルドの中で確かめる。
/// 実行時の挙動は `DialogCurrentPageTests` などが受け持つ。
@MainActor
enum DialogCurrentPageCompileChecks {
    /// 基準領域に表示中のページを指定できる。
    static func acceptsCurrentPageLayoutArea(contentView: UIView) {
        contentView.ksDialogOptions = DialogOptions(layoutArea: .currentPage)
        var options = DialogOptions()
        options.layoutArea = .currentPage
        _ = options
    }

    /// ページの View を返す関数を登録できる (エラーを投げない関数・投げる関数のどちらでも)。
    static func registersViewProvider(pageViewController: UIViewController) {
        DialogCurrentPage.provider = { pageViewController.view }
        DialogCurrentPage.provider = {
            guard pageViewController.isViewLoaded else { throw CancellationError() }
            return pageViewController.view
        }
    }

    /// 登録を外すと既定の探し方に戻る。
    static func clearsViewProvider() {
        DialogCurrentPage.provider = nil
    }

    /// SwiftUI の View を表示中のページとして名乗らせられる。
    static func marksSwiftUIViewAsCurrentPage() -> some View {
        NavigationStack {
            Text("Page")
                .markAsDialogCurrentPage()
        }
    }
}
#endif
