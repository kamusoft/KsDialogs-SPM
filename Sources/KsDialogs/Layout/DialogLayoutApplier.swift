#if canImport(UIKit)
import UIKit

/// 実効値のレイアウトを中身の View へ反映する部品。
///
/// `DialogLayoutResolver` の呼び出しと、その解を Auto Layout の制約へ落とすところを受け持つ。
/// どの実効値を採るか (供給の合成とその固定) を決めるのは器の側で、
/// この部品は渡された実効値をそのまま反映する。
@MainActor
final class DialogLayoutApplier {
    /// 決まったサイズを与える制約の優先度。
    /// 有効領域による頭打ち (必須) には負け、内容サイズの主張には勝つ強さにする。
    private static let resolvedSizePriority = UILayoutPriority(999)

    /// レイアウトの入力になるウィンドウの状況。同じ値なら制約を入れ直さない。
    private struct LayoutInput: Equatable {
        let bounds: CGRect
        let insets: DialogEdgeInsets
    }

    /// 配置する中身の View。
    private let contentView: UIView

    /// 中身を載せている器の View。位置と有効領域の基準になる。
    private var containerView: UIView?

    private var activeContentConstraints: [NSLayoutConstraint] = []
    private var contentWidthConstraint: NSLayoutConstraint?
    private var contentMaxWidthConstraint: NSLayoutConstraint?
    private var contentHorizontalPositionConstraint: NSLayoutConstraint?
    private var contentHeightConstraint: NSLayoutConstraint?
    private var contentMaxHeightConstraint: NSLayoutConstraint?
    private var contentVerticalPositionConstraint: NSLayoutConstraint?
    private var appliedLayoutInput: LayoutInput?

    /// - Parameter contentView: 配置する中身の View
    init(contentView: UIView) {
        self.contentView = contentView
    }

    /// 中身を器の View へ載せ、以降の基準をその View にする。
    /// 制約はこの呼び出しでは組まず、`rebuildConstraints(for:)` で組む。
    func install(in containerView: UIView) {
        self.containerView = containerView
        contentView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentView)
    }

    /// 中身の View の制約を組む。
    /// どの制約を張るか (サイズを固定するか・どの端を固定するか) はレイアウト属性だけで決まるため、
    /// 実効値が確定している間はウィンドウの変化に応じて定数だけを更新する。
    /// 実効値そのものが変わったときだけ張り直す。
    func rebuildConstraints(for layout: DialogLayout) {
        guard let containerView else { return }
        NSLayoutConstraint.deactivate(activeContentConstraints)
        contentWidthConstraint = nil
        contentHeightConstraint = nil
        appliedLayoutInput = nil
        let solution = layoutSolution(for: layout, in: containerView)
        var constraints: [NSLayoutConstraint] = []

        if solution.horizontal.size != nil {
            let widthConstraint = contentView.widthAnchor.constraint(equalToConstant: 0)
            widthConstraint.priority = Self.resolvedSizePriority
            contentWidthConstraint = widthConstraint
            constraints.append(widthConstraint)
        }
        let maxWidthConstraint = contentView.widthAnchor.constraint(lessThanOrEqualToConstant: 0)
        contentMaxWidthConstraint = maxWidthConstraint
        constraints.append(maxWidthConstraint)

        let horizontalPositionConstraint = makeHorizontalPositionConstraint(
            solution.horizontal.position,
            in: containerView
        )
        contentHorizontalPositionConstraint = horizontalPositionConstraint
        constraints.append(horizontalPositionConstraint)

        if solution.vertical.size != nil {
            let heightConstraint = contentView.heightAnchor.constraint(equalToConstant: 0)
            heightConstraint.priority = Self.resolvedSizePriority
            contentHeightConstraint = heightConstraint
            constraints.append(heightConstraint)
        }
        let maxHeightConstraint = contentView.heightAnchor.constraint(lessThanOrEqualToConstant: 0)
        contentMaxHeightConstraint = maxHeightConstraint
        constraints.append(maxHeightConstraint)

        let verticalPositionConstraint = makeVerticalPositionConstraint(
            solution.vertical.position,
            in: containerView
        )
        contentVerticalPositionConstraint = verticalPositionConstraint
        constraints.append(verticalPositionConstraint)

        updateForCurrentBounds(layout: layout)
        NSLayoutConstraint.activate(constraints)
        activeContentConstraints = constraints
    }

    /// ウィンドウの大きさか可視領域が変わったときだけ制約の値を入れ直す。
    func updateForCurrentBounds(layout: DialogLayout) {
        guard let containerView else { return }
        let bounds = containerView.bounds
        let visibleAreaInsets = DialogEdgeInsets(containerView.safeAreaInsets)
        if let appliedLayoutInput, appliedLayoutInput == LayoutInput(bounds: bounds, insets: visibleAreaInsets) {
            return
        }
        appliedLayoutInput = LayoutInput(bounds: bounds, insets: visibleAreaInsets)
        apply(
            DialogLayoutResolver.resolve(
                layout: layout,
                bounds: bounds,
                visibleAreaInsets: visibleAreaInsets
            )
        )
    }

    /// 水平方向の位置を固定する制約を、器の View の左端を基準に作る。
    private func makeHorizontalPositionConstraint(
        _ position: DialogAxisLayout.Position,
        in containerView: UIView
    ) -> NSLayoutConstraint {
        switch position {
        case .leadingEdge:
            return contentView.leftAnchor.constraint(equalTo: containerView.leftAnchor)
        case .center:
            return contentView.centerXAnchor.constraint(equalTo: containerView.leftAnchor)
        case .trailingEdge:
            return contentView.rightAnchor.constraint(equalTo: containerView.leftAnchor)
        }
    }

    /// 垂直方向の位置を固定する制約を、器の View の上端を基準に作る。
    private func makeVerticalPositionConstraint(
        _ position: DialogAxisLayout.Position,
        in containerView: UIView
    ) -> NSLayoutConstraint {
        switch position {
        case .leadingEdge:
            return contentView.topAnchor.constraint(equalTo: containerView.topAnchor)
        case .center:
            return contentView.centerYAnchor.constraint(equalTo: containerView.topAnchor)
        case .trailingEdge:
            return contentView.bottomAnchor.constraint(equalTo: containerView.topAnchor)
        }
    }

    private func layoutSolution(
        for layout: DialogLayout,
        in containerView: UIView
    ) -> (horizontal: DialogAxisLayout, vertical: DialogAxisLayout) {
        DialogLayoutResolver.resolve(
            layout: layout,
            bounds: containerView.bounds,
            visibleAreaInsets: DialogEdgeInsets(containerView.safeAreaInsets)
        )
    }

    private func apply(_ solution: (horizontal: DialogAxisLayout, vertical: DialogAxisLayout)) {
        contentWidthConstraint?.constant = solution.horizontal.size ?? 0
        contentMaxWidthConstraint?.constant = solution.horizontal.maxSize
        contentHorizontalPositionConstraint?.constant = solution.horizontal.position.constant
        contentHeightConstraint?.constant = solution.vertical.size ?? 0
        contentMaxHeightConstraint?.constant = solution.vertical.maxSize
        contentVerticalPositionConstraint?.constant = solution.vertical.position.constant
    }
}
#endif
