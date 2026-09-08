#if canImport(UIKit)
import UIKit

/// Toast の器のルートになる面。
///
/// Loading の器のルートと違い、この面は入力を一切受け取らない。
/// `hitTest` が常に nil を返すため、Toast の面へのタッチは自分にも中身にも当たらず、
/// 背後のページ要素がそのまま反応する (core/ADR-0031)。
/// 対話可能な部品をカスタム Toast View に置いても反応しないのはこのためである。
///
/// Toast の器は提示機構を通らないため、`UIViewController` の出現通知に頼らず
/// この View の生の通知でレイアウトの節目を捉える。
final class ToastContainerRootView: UIView {
    /// ウィンドウに載ったときに呼ばれる。
    var onAttachedToWindow: (() -> Void)?

    /// レイアウトパスに入るときに呼ばれる。
    var onWillLayoutSubviews: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        onAttachedToWindow?()
    }

    override func layoutSubviews() {
        onWillLayoutSubviews?()
        super.layoutSubviews()
    }

    /// すべてのタッチを素通しする。自分も子も当たり判定を持たない。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}
#endif
