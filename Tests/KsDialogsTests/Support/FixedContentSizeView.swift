#if canImport(UIKit)
import UIKit

/// 指定した内容サイズを要求する中身の View。
/// 共通ケース表の contentSize をそのまま内容サイズとして与えるために使う。
final class FixedContentSizeView: UIView {
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
