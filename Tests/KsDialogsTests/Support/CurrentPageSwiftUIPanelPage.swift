#if canImport(UIKit)
import KsDialogs
import SwiftUI

/// ナビゲーションバーを持つタブの画面。`NavigationStack` の中身の枠に `markAsDialogCurrentPage()` を付ける。
struct CurrentPageSwiftUIPanelPage: View {
    var body: some View {
        NavigationStack {
            Color.clear
                .markAsDialogCurrentPage()
                .navigationTitle("Panel")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
