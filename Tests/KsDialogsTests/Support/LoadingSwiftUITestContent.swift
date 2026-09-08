#if canImport(UIKit)
import SwiftUI

/// SwiftUI の中身が画面に現れたことを書き留める。
@MainActor
final class LoadingTestAppearanceRecorder {
    private(set) var appearCount = 0

    func recordAppear() {
        appearCount += 1
    }
}

/// 指定した内容サイズを要求し、出現を書き留める SwiftUI の中身。
///
/// Loading の器は提示機構を通らないため、中身のホストへ出現通知が届くかどうかを
/// この中身の `onAppear` で観察する。
struct LoadingSwiftUIProbeContent: View {
    let contentSize: CGSize
    let recorder: LoadingTestAppearanceRecorder

    var body: some View {
        Color.clear
            .frame(width: contentSize.width, height: contentSize.height)
            .onAppear { recorder.recordAppear() }
    }
}
#endif
