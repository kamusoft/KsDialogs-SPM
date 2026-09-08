#if canImport(UIKit)
import UIKit
#endif

/// 4辺それぞれの余白 (論理単位 pt)。
public struct DialogEdgeInsets: Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// 4辺すべてに同じ値を与える。
    public init(all: Double) {
        self.init(top: all, left: all, bottom: all, right: all)
    }

    /// 4辺すべてが 0 の余白。
    public static let zero = DialogEdgeInsets(all: 0)
}

#if canImport(UIKit)
extension DialogEdgeInsets {
    /// UIKit の余白表現から作る。
    init(_ insets: UIEdgeInsets) {
        self.init(
            top: Double(insets.top),
            left: Double(insets.left),
            bottom: Double(insets.bottom),
            right: Double(insets.right)
        )
    }
}
#endif
