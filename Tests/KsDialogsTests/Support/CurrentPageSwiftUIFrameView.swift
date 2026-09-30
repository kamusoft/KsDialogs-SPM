#if canImport(UIKit)
import KsDialogs
import SwiftUI

/// 上端から高さ 300 の枠だけに `markAsDialogCurrentPage()` を付けた画面。
/// 枠の矩形がページ全体の safe area と見分けられ、かつ既定の余白を除いても内容 (高さ 180) が収まる高さにしてある。
struct CurrentPageSwiftUIFrameView: View {
    static let markedHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: Self.markedHeight)
                .markAsDialogCurrentPage()
            Color.clear
        }
    }
}
#endif
