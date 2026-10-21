#if canImport(UIKit)
import SwiftUI
import UIKit

/// 重ねた View と同じ矩形に置かれる、見えも当たり判定も持たない UIView の目印。
///
/// `.background` や `.overlay` で中身に重ね、描かれた位置を `SwiftUIDrawnFrameProbe` から読む。
struct SwiftUIDrawnFrameMarker: UIViewRepresentable {
    let probe: SwiftUIDrawnFrameProbe

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        probe.markerView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        probe.markerView = uiView
    }
}
#endif
