#if canImport(UIKit)
import UIKit

@testable import KsDialogs
#endif

/// 共通ケース表の1ケースが指定するレイアウト属性 (供給を合成した後の実効値)。
/// 書かれていない属性は nil で、そのまま契約の既定値を意味する。
struct DialogLayoutCaseAttributes: Decodable, Sendable {
    let layoutArea: String?
    let dialogMargin: DialogLayoutCaseMargin?
    let proportionalWidth: Double?
    let proportionalHeight: Double?
    let horizontalAlignment: String?
    let verticalAlignment: String?
    let offsetX: Double?
    let offsetY: Double?
    let overlayColor: String?
}

#if canImport(UIKit)
extension DialogLayoutCaseAttributes {
    /// ケースの実効値のうち、静的メタ属性にあたる分。
    var options: DialogOptions {
        var options = DialogOptions()
        if let layoutArea = Self.layoutArea(layoutArea) {
            options.layoutArea = layoutArea
        }
        if let dialogMargin {
            options.dialogMargin = dialogMargin.insets
        }
        if let proportionalWidth {
            options.proportionalWidth = proportionalWidth
        }
        if let proportionalHeight {
            options.proportionalHeight = proportionalHeight
        }
        if let overlayColor = Self.color(overlayColor) {
            options.overlayColor = overlayColor
        }
        return options
    }

    /// ケースの実効値のうち、動的メタ属性にあたる分。
    var placement: DialogPlacement {
        var placement = DialogPlacement()
        if let horizontalAlignment = Self.alignment(horizontalAlignment) {
            placement.horizontalAlignment = horizontalAlignment
        }
        if let verticalAlignment = Self.alignment(verticalAlignment) {
            placement.verticalAlignment = verticalAlignment
        }
        if let offsetX {
            placement.offsetX = offsetX
        }
        if let offsetY {
            placement.offsetY = offsetY
        }
        return placement
    }

    private static func alignment(_ name: String?) -> DialogAlignment? {
        switch name {
        case "start": return .start
        case "center": return .center
        case "end": return .end
        case "fill": return .fill
        default: return nil
        }
    }

    private static func layoutArea(_ name: String?) -> DialogLayoutArea? {
        switch name {
        case "window": return .window
        case "visibleArea": return .visibleArea
        default: return nil
        }
    }

    /// `#AARRGGBB` 形式の色を読む (形態間の interop 境界と同じ ARGB 並び)。
    private static func color(_ text: String?) -> UIColor? {
        guard let text, text.hasPrefix("#") else { return nil }
        let digits = String(text.dropFirst())
        guard digits.count == 8, let packed = UInt32(digits, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((packed >> 16) & 0xFF) / 255,
            green: CGFloat((packed >> 8) & 0xFF) / 255,
            blue: CGFloat(packed & 0xFF) / 255,
            alpha: CGFloat((packed >> 24) & 0xFF) / 255
        )
    }
}
#endif
