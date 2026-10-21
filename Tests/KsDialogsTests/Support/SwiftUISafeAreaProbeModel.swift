#if canImport(UIKit)
import Observation
import SwiftUI

/// 安全領域を記録する SwiftUI の中身が求める大きさ。表示中に変えると中身の要求サイズが変わる。
///
/// `isFixedSize` が false なら大きさが可変で、理想の大きさを求めつつ提案された大きさまで縮む。
/// そのとき `minHeight` があれば、高さはそこまでしか縮まない (一部だけ縮む中身)。
/// true なら理想の大きさに固定し、縮まない。
@MainActor
@Observable
final class SwiftUISafeAreaProbeModel {
    var idealWidth: CGFloat
    var idealHeight: CGFloat
    var minHeight: CGFloat?
    var isFixedSize: Bool

    init(idealWidth: CGFloat = 200, idealHeight: CGFloat = 100, minHeight: CGFloat? = nil, isFixedSize: Bool = false) {
        self.idealWidth = idealWidth
        self.idealHeight = idealHeight
        self.minHeight = minHeight
        self.isFixedSize = isFixedSize
    }
}
#endif
