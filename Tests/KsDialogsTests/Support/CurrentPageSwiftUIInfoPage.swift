#if canImport(UIKit)
import KsDialogs
import SwiftUI

/// タイトルバーを持たないタブの画面。中身の枠 (safe area の内側全体) に `markAsDialogCurrentPage()` を付ける。
struct CurrentPageSwiftUIInfoPage: View {
    var body: some View {
        Color.clear
            .markAsDialogCurrentPage()
    }
}
#endif
