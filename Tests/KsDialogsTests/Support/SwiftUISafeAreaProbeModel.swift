#if canImport(UIKit)
import Observation
import SwiftUI

/// 安全領域を記録する SwiftUI の中身が求める大きさ。表示中に変えると中身の要求サイズが変わる。
@MainActor
@Observable
final class SwiftUISafeAreaProbeModel {
    var idealWidth: CGFloat
    var idealHeight: CGFloat

    init(idealWidth: CGFloat = 200, idealHeight: CGFloat = 100) {
        self.idealWidth = idealWidth
        self.idealHeight = idealHeight
    }
}
#endif
