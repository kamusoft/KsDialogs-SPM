#if canImport(UIKit)
import CoreGraphics

/// レイアウト属性とウィンドウの状況から、軸ごとのレイアウト解を導く。
///
/// 水平と垂直は独立に解かれ、軸をまたぐ依存はない (core/ADR-0007)。
enum DialogLayoutResolver {
    /// 水平・垂直の解をまとめて求める。
    /// - Parameters:
    ///   - layout: 丸め済みのレイアウト属性
    ///   - bounds: ウィンドウの矩形 (原点は左上)
    ///   - visibleAreaInsets: ウィンドウから可視領域を狭めるシステム領域の幅
    static func resolve(
        layout: DialogLayout,
        bounds: CGRect,
        visibleAreaInsets: DialogEdgeInsets
    ) -> (horizontal: DialogAxisLayout, vertical: DialogAxisLayout) {
        let insets: DialogEdgeInsets
        switch layout.layoutArea {
        case .window:
            insets = .zero
        case .visibleArea:
            insets = visibleAreaInsets
        }

        let horizontal = resolveAxis(
            regionOrigin: Double(bounds.minX) + insets.left,
            regionLength: Double(bounds.width) - insets.left - insets.right,
            marginLeading: layout.dialogMargin.left,
            marginTrailing: layout.dialogMargin.right,
            proportion: layout.proportionalWidth,
            alignment: layout.horizontalAlignment,
            offset: layout.offsetX
        )
        let vertical = resolveAxis(
            regionOrigin: Double(bounds.minY) + insets.top,
            regionLength: Double(bounds.height) - insets.top - insets.bottom,
            marginLeading: layout.dialogMargin.top,
            marginTrailing: layout.dialogMargin.bottom,
            proportion: layout.proportionalHeight,
            alignment: layout.verticalAlignment,
            offset: layout.offsetY
        )
        return (horizontal, vertical)
    }

    /// 1軸分を解く。
    /// - Parameters:
    ///   - regionOrigin: 基準 rect の前端
    ///   - regionLength: 基準 rect の軸長 (比率サイズの基準)
    ///   - marginLeading: 前端側の余白
    ///   - marginTrailing: 後端側の余白
    ///   - proportion: 比率指定 (nil で未指定)
    ///   - alignment: 配置
    ///   - offset: 配置後の移動量
    static func resolveAxis(
        regionOrigin: Double,
        regionLength: Double,
        marginLeading: Double,
        marginTrailing: Double,
        proportion: Double?,
        alignment: DialogAlignment,
        offset: Double
    ) -> DialogAxisLayout {
        let effectiveAreaOrigin = regionOrigin + marginLeading
        let effectiveAreaLength = max(0, regionLength - marginLeading - marginTrailing)

        // サイズは 比率 > fill 配置 > 内容 の優先順で決まる。
        // 比率の基準は余白を控除する前の基準 rect、fill の基準は控除後の有効領域。
        // 内容サイズは View 自身の主張に委ねるため、ここでは nil を返す (core/ADR-0014)。
        let size: Double?
        let isFilled: Bool
        if let proportion {
            size = proportion * regionLength
            isFilled = false
        } else if alignment == .fill {
            size = effectiveAreaLength
            isFilled = true
        } else {
            size = nil
            isFilled = false
        }

        // サイズの決め方として fill が採用されなかった軸の fill 配置は中央として扱う。
        let effectiveAlignment: DialogAlignment = (alignment == .fill && !isFilled) ? .center : alignment
        let position: DialogAxisLayout.Position
        switch effectiveAlignment {
        case .start, .fill:
            position = .leadingEdge(CGFloat(effectiveAreaOrigin + offset))
        case .center:
            position = .center(CGFloat(effectiveAreaOrigin + effectiveAreaLength / 2 + offset))
        case .end:
            position = .trailingEdge(CGFloat(effectiveAreaOrigin + effectiveAreaLength + offset))
        }

        return DialogAxisLayout(
            size: size.map { CGFloat(max(0, $0)) },
            maxSize: CGFloat(effectiveAreaLength),
            position: position
        )
    }
}
#endif
