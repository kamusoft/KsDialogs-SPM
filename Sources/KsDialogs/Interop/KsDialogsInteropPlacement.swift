#if canImport(UIKit)
import Foundation

/// 互換面が運ぶ配置の判別。
/// Swift の enum はそのままでは ObjC 表現に出せないため、整数値の判別として運ぶ。
@objc(KSDInteropDialogAlignment)
public enum KsDialogsInteropAlignment: Int, Sendable {
    case start = 0
    case center = 1
    case end = 2
    case fill = 3
}

/// 互換面が運ぶ動的メタ属性 (置き場所)。
///
/// 共有コード (KMP) の show 引数で指定された置き場所を、ObjC 表現に出せる形 (判別2つと数値2つ) で運ぶ。
/// この面はレイアウト計算も値の正規化も行わず、受け取った値をそのままライブラリの `DialogPlacement` へ写す
/// (core/ADR-0001)。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない
/// (Swift の入口は `DialogPlacement`)。
@objc(KSDInteropDialogPlacement)
public final class KsDialogsInteropPlacement: NSObject, Sendable {
    /// 水平方向の配置。
    @objc public let horizontalAlignment: KsDialogsInteropAlignment

    /// 垂直方向の配置。
    @objc public let verticalAlignment: KsDialogsInteropAlignment

    /// 配置を決めた後に加える水平方向の移動量。正の値で右へ動く。
    @objc public let offsetX: Double

    /// 配置を決めた後に加える垂直方向の移動量。正の値で下へ動く。
    @objc public let offsetY: Double

    @objc(initWithHorizontalAlignment:verticalAlignment:offsetX:offsetY:)
    public init(
        horizontalAlignment: KsDialogsInteropAlignment,
        verticalAlignment: KsDialogsInteropAlignment,
        offsetX: Double,
        offsetY: Double
    ) {
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.offsetX = offsetX
        self.offsetY = offsetY
        super.init()
    }
}

extension DialogAlignment {
    /// 互換面の配置をライブラリの配置へ写す。
    init(_ alignment: KsDialogsInteropAlignment) {
        switch alignment {
        case .start: self = .start
        case .center: self = .center
        case .end: self = .end
        case .fill: self = .fill
        }
    }
}

extension DialogPlacement {
    /// 互換面の置き場所をライブラリの置き場所へ写す。
    init(_ placement: KsDialogsInteropPlacement) {
        self.init(
            horizontalAlignment: DialogAlignment(placement.horizontalAlignment),
            verticalAlignment: DialogAlignment(placement.verticalAlignment),
            offsetX: placement.offsetX,
            offsetY: placement.offsetY
        )
    }
}
#endif
