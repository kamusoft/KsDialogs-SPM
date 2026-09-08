#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// 添付値の供給を永久に知らせない中身。
///
/// 宣言的 UI の供給が届かないまま到達待ちの上限に達した状況を作り、
/// そのとき器が契約既定値で提示を続けることを観察するために使う。
final class NeverResolvingAttributeSupplyView: UIView, DialogAttributeSupplyProbe {
    let hasResolvedAttributeSupply = false

    private let contentSize: CGSize

    init(contentSize: CGSize) {
        self.contentSize = contentSize
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("この View は storyboard からの生成に対応しない")
    }

    override var intrinsicContentSize: CGSize {
        contentSize
    }
}
#endif
