#if canImport(UIKit)
import KsDialogs
import SwiftUI

/// SwiftUI の `TabView` の中の `NavigationStack` に載せた画面。中身の枠に `markAsDialogCurrentPage()` を付ける。
struct CurrentPageSwiftUITabHostView: View {
    var body: some View {
        TabView {
            NavigationStack {
                Color.clear
                    .markAsDialogCurrentPage()
                    .navigationTitle("Panel")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Panel", systemImage: "slider.horizontal.3") }

            Text("Info")
                .tabItem { Label("Info", systemImage: "info.circle") }
        }
    }
}
#endif
