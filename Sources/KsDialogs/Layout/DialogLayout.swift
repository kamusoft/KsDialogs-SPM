#if canImport(UIKit)
import UIKit

/// 実効値を丸め終えたレイアウト属性一式。
/// 未指定を表す値 (0 以下の比率・非有限値) はここで `nil` へ畳み込まれるため、
/// 以降の計算は「指定があるかどうか」だけを見ればよい。
///
/// 供給が書き換わったかの判定にもこの型の等値を使う。非有限値は丸め終えているため、
/// 「同じ値を読み直しても等しくならない」ことが起きない。
struct DialogLayout: Equatable {
    let proportionalWidth: Double?
    let proportionalHeight: Double?
    let horizontalAlignment: DialogAlignment
    let verticalAlignment: DialogAlignment
    let offsetX: Double
    let offsetY: Double
    let dialogMargin: DialogEdgeInsets
    let layoutArea: DialogLayoutArea
    let overlayColor: UIColor
    let isCanceledOnTouchOutside: Bool

    /// 供給を合成し終えた実効値から作る。
    init(options: DialogOptions = DialogOptions(), placement: DialogPlacement = DialogPlacement()) {
        proportionalWidth = Self.normalizedProportion(options.proportionalWidth)
        proportionalHeight = Self.normalizedProportion(options.proportionalHeight)
        horizontalAlignment = placement.horizontalAlignment
        verticalAlignment = placement.verticalAlignment
        offsetX = Self.normalizedOffset(placement.offsetX)
        offsetY = Self.normalizedOffset(placement.offsetY)
        dialogMargin = Self.normalizedMargin(options.dialogMargin)
        layoutArea = options.layoutArea
        overlayColor = options.overlayColor
        isCanceledOnTouchOutside = options.isCanceledOnTouchOutside
    }

    /// 「show 引数 > コンテンツ添付 > 契約既定値」の優先順で読んだ、その時点の実効値 (core/ADR-0015)。
    /// - Parameters:
    ///   - showPlacement: show の引数で渡された配置。nil でなければ添付された placement をまるごと置換する
    ///   - contentView: 属性の添付を読む中身の View
    @MainActor
    static func composed(showPlacement: DialogPlacement?, attachedOn contentView: UIView) -> DialogLayout {
        DialogLayout(
            options: contentView.ksDialogOptions ?? DialogOptions(),
            placement: showPlacement ?? contentView.ksDialogPlacement ?? DialogPlacement()
        )
    }

    /// 比率指定を有効域 0 < 値 ≤ 1 に収める。0 以下と非有限値は未指定。
    private static func normalizedProportion(_ value: Double) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        return min(value, 1)
    }

    /// 移動量を有限値に限る。非有限値は既定値の 0。
    private static func normalizedOffset(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    /// 余白を辺ごとに丸める。負の辺は下限の 0 へ、非有限値の辺は既定値へ戻す。
    private static func normalizedMargin(_ margin: DialogEdgeInsets) -> DialogEdgeInsets {
        DialogEdgeInsets(
            top: normalizedMarginEdge(margin.top, default: defaultMargin.top),
            left: normalizedMarginEdge(margin.left, default: defaultMargin.left),
            bottom: normalizedMarginEdge(margin.bottom, default: defaultMargin.bottom),
            right: normalizedMarginEdge(margin.right, default: defaultMargin.right)
        )
    }

    private static func normalizedMarginEdge(_ value: Double, default defaultValue: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return max(0, value)
    }

    /// 契約が定める余白の既定値。
    private static let defaultMargin = DialogOptions().dialogMargin
}
#endif
