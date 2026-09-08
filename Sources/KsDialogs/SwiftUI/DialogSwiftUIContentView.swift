#if canImport(UIKit)
import UIKit

/// SwiftUI の中身を器へ載せるための View。
///
/// 添付 DSL (`ksDialogOptions` / `ksDialogPlacement`) で供給された値を preference 経由で受け取り、
/// 自分自身の添付面へ書き戻す。これにより宣言的 UI の供給も従来 View 系とまったく同じ
/// 合成経路 (show 引数 > コンテンツ添付 > 契約既定値) に載る (core/ADR-0015)。
///
/// 供給が届くのはホストのレイアウトの中なので、器はこの View が持つ到達状態を見て
/// 実効値を固定する時点を決める。
@MainActor
final class DialogSwiftUIContentView: UIView, DialogAttributeSupplyProbe {
    private(set) var hasResolvedAttributeSupply = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("This View does not support instantiation from a storyboard.")
    }

    /// ホストの View を全面に敷く。中身が要求するサイズはこの View のサイズとして器へ伝わる。
    func embed(_ hostedView: UIView) {
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostedView.leftAnchor.constraint(equalTo: leftAnchor),
            hostedView.rightAnchor.constraint(equalTo: rightAnchor)
        ])
    }

    /// preference から届いた添付値を自分の添付面へ書き戻す。
    func resolveAttributeSupply(_ attachment: DialogAttributeAttachment) {
        hasResolvedAttributeSupply = true
        ksDialogOptions = attachment.options
        ksDialogPlacement = attachment.placement
        ksDialogTransition = attachment.transition
    }
}
#endif
