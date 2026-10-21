#if canImport(UIKit)
import SwiftUI
import UIKit

/// 中身に重ね、中身が置かれた大きさが変わるたびに知らせる、見えも当たり判定も持たない UIView。
///
/// 理想の大きさを変えずに縮められる範囲だけが変わった中身は、ホストが求める大きさを変えないため、
/// 器の側からはその変化が見えない。中身と同じ矩形に置かれるこの View の大きさの変化で、
/// 中身が置き直されたことを捉える。
struct DialogSwiftUIContentLayoutReader: UIViewRepresentable {
    let onResize: @MainActor () -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onResize = onResize
        return view
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {
        uiView.onResize = onResize
    }

    /// 置かれた大きさが前と変わったときだけ知らせる。
    final class ReaderView: UIView {
        var onResize: (@MainActor () -> Void)?
        private var lastSize: CGSize?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != lastSize else { return }
            lastSize = bounds.size
            onResize?()
        }
    }
}
#endif
