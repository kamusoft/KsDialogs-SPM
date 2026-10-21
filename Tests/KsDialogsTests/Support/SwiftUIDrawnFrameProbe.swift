#if canImport(UIKit)
import UIKit

/// SwiftUI の中身に重ねた UIView の目印から、中身が実際に描かれた矩形 (window 座標) を読む口。
///
/// 目印は SwiftUI のレイアウトで実際に置かれた位置へ配置されるため、中身から読む geometry
/// (`onGeometryChange` 等) と違い、描かれた位置そのものを表す。
@MainActor
final class SwiftUIDrawnFrameProbe {
    weak var markerView: UIView?

    /// 目印の矩形 (window 座標)。目印がまだ window に載っていなければ nil。
    var windowFrame: CGRect? {
        guard let markerView, markerView.window != nil else { return nil }
        return markerView.convert(markerView.bounds, to: nil)
    }
}
#endif
