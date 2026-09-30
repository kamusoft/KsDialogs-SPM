#if canImport(UIKit)
import SwiftUI

/// 名乗らせた枠の背面に敷き、枠と同じ矩形の UIKit の View を台帳へ載せる。
struct DialogCurrentPageMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> DialogCurrentPageMarkerView {
        DialogCurrentPageMarkerView(ledger: .shared)
    }

    func updateUIView(_ uiView: DialogCurrentPageMarkerView, context: Context) {}
}
#endif
