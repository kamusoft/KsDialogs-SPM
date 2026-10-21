#if canImport(UIKit)
import KsDialogs
import SwiftUI
import Testing

/// 文言と操作部品を並べた、縮まない帯の SwiftUI の中身 (地色を持つ)。窓全体を基準領域にする。
///
/// 帯 (文言とボタンの並び) と地色のそれぞれに UIView の目印を重ね、描かれた位置を読めるようにする。
/// 安全領域の扱いは、無視しない・一番外側で無視する・地色だけ無視する、の 3 通りを選べる。
struct EdgeConfirmSwiftUIContent: View {
    enum SafeAreaHandling: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case respects = "無視しない"
        case ignoresOutermost = "一番外側で無視する"
        case ignoresBackgroundOnly = "地色だけ無視する"

        var testDescription: String { rawValue }
    }

    let handling: SafeAreaHandling
    let band: SwiftUIDrawnFrameProbe
    let background: SwiftUIDrawnFrameProbe

    var body: some View {
        shaped.ksDialogOptions(DialogOptions(layoutArea: .window))
    }

    @ViewBuilder
    private var shaped: some View {
        switch handling {
        case .respects:
            bandContent.background { backgroundLayer }
        case .ignoresOutermost:
            bandContent.background { backgroundLayer }.ignoresSafeArea(.container)
        case .ignoresBackgroundOnly:
            bandContent.background { backgroundLayer.ignoresSafeArea(.container) }
        }
    }

    private var bandContent: some View {
        VStack(spacing: 16) {
            Text("この色を保存しますか?")
            HStack(spacing: 24) {
                Button("いいえ") {}
                Button("はい") {}
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background { SwiftUIDrawnFrameMarker(probe: band) }
    }

    private var backgroundLayer: some View {
        Color.gray.overlay { SwiftUIDrawnFrameMarker(probe: background) }
    }
}
#endif
