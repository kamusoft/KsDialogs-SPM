#if canImport(UIKit)
import SwiftUI

/// 指定した内容サイズを要求する SwiftUI の中身。
/// 共通ケース表の contentSize をそのまま理想サイズとして与えるために使う。
struct FixedSizeSwiftUIContent: View {
    let contentSize: CGSize

    var body: some View {
        Color.clear.frame(width: contentSize.width, height: contentSize.height)
    }
}
#endif
