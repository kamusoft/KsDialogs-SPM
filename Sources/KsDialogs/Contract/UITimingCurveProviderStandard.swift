#if canImport(UIKit)
import UIKit

/// プリセットが既定で使うイージング。
public extension UITimingCurveProvider where Self == UICubicTimingParameters {
    /// 加速して減速する標準の曲線。プリセットの `easing` を省略したときの値になる。
    static var standard: UICubicTimingParameters {
        UICubicTimingParameters(animationCurve: .easeInOut)
    }
}
#endif
