#if canImport(UIKit)
import UIKit
import os

/// 実効値のレイアウトを中身の View へ反映する部品。
///
/// `DialogLayoutResolver` の呼び出しと、その解を Auto Layout の制約へ落とすところを受け持つ。
/// どの実効値を採るか (供給の合成とその固定) を決めるのは器の側で、
/// この部品は渡された実効値をそのまま反映する。
///
/// 基準領域が表示中のページのときは、ページの基準矩形をウィンドウからの4辺の幅へ直して
/// 計算へ渡す。ページへの問い合わせは表示の開始時と、ウィンドウの寸法・可視領域の余白が
/// 変わったときだけ行う (再配置のきっかけはこの2つだけ)。ウィンドウが変わった同じレイアウト
/// パスの中では、ページ側 (タブバーの高さ・safe area) の更新がまだ終わっていないことがあるため、
/// 同じきっかけに対して次の main の番でもう一度だけ問い合わせ、結果が違えば入れ直す。
@MainActor
final class DialogLayoutApplier {
    /// 表示中のページが得られなかったことを知らせる記録口。
    private static let logger = Logger(subsystem: "jp.kamusoft.ksdialogs", category: "layout")

    /// 決まったサイズを与える制約の優先度。
    /// 有効領域による頭打ち (必須) には負け、内容サイズの主張には勝つ強さにする。
    private static let resolvedSizePriority = UILayoutPriority(999)

    /// レイアウトの入力になるウィンドウの状況。同じ値なら制約を入れ直さない。
    /// 載っているウィンドウが替われば表示中のページも替わり得るため、ウィンドウも入力に含める。
    private struct LayoutInput: Equatable {
        let bounds: CGRect
        let insets: DialogEdgeInsets
        let window: ObjectIdentifier?
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

    /// 表示中のページを決める取得元の並び。表示の開始時点の登録内容で固定される。
    private let currentPageResolver: DialogCurrentPageResolver

    /// 表示中のページが得られずに出した診断の本文 (出した順)。
    private(set) var currentPageDiagnostics: [String] = []

    /// 今の制約に反映している、表示中のページの4辺の幅。ページを使っていなければ nil。
    private var appliedCurrentPageInsets: DialogEdgeInsets?

    /// ウィンドウ変化のあとの、もう一度の問い合わせ。新しい変化が来たら取り消して置き換える。
    private var settlingPageQuery: Task<Void, Never>?

    /// 表示の開始時点の登録内容で、表示中のページの取得元を固定する。
    /// - Parameter contentView: 配置する中身の View
    convenience init(contentView: UIView) {
        self.init(contentView: contentView, currentPageResolver: .capturingRegistration())
    }

    /// - Parameters:
    ///   - contentView: 配置する中身の View
    ///   - currentPageResolver: 基準領域が表示中のページのときに使う取得元の並び
    init(contentView: UIView, currentPageResolver: DialogCurrentPageResolver) {
        self.contentView = contentView
        self.currentPageResolver = currentPageResolver
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
        let input = LayoutInput(
            bounds: bounds,
            insets: visibleAreaInsets,
            window: containerView.window.map(ObjectIdentifier.init)
        )
        if let appliedLayoutInput, appliedLayoutInput == input {
            return
        }
        appliedLayoutInput = input
        let pageInsets = currentPageInsets(
            for: layout,
            in: containerView,
            visibleAreaInsets: visibleAreaInsets,
            reportsUnresolved: true
        )
        appliedCurrentPageInsets = pageInsets
        apply(
            DialogLayoutResolver.resolve(
                layout: layout,
                bounds: bounds,
                visibleAreaInsets: visibleAreaInsets,
                currentPageInsets: pageInsets
            )
        )
        scheduleSettlingPageQuery(layout: layout, input: input)
    }

    /// 同じウィンドウ変化に対するもう一度の問い合わせを、次の main の番に予約する。
    private func scheduleSettlingPageQuery(layout: DialogLayout, input: LayoutInput) {
        settlingPageQuery?.cancel()
        settlingPageQuery = nil
        guard layout.layoutArea == .currentPage, input.window != nil else { return }
        settlingPageQuery = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            self?.requeryCurrentPage(layout: layout, input: input)
        }
    }

    /// ページ側のレイアウトが落ち着いたあとで問い合わせ直し、結果が違えば制約を入れ直す。
    /// その間に次のウィンドウ変化が反映されていたら何もしない (そちらの問い合わせが正)。
    /// 見つからなかったときは直前の結果を保ち、診断も重ねて出さない。
    private func requeryCurrentPage(layout: DialogLayout, input: LayoutInput) {
        guard let containerView, appliedLayoutInput == input else { return }
        guard let pageInsets = currentPageInsets(
            for: layout,
            in: containerView,
            visibleAreaInsets: input.insets,
            reportsUnresolved: false
        ), pageInsets != appliedCurrentPageInsets else { return }
        appliedCurrentPageInsets = pageInsets
        apply(
            DialogLayoutResolver.resolve(
                layout: layout,
                bounds: input.bounds,
                visibleAreaInsets: input.insets,
                currentPageInsets: pageInsets
            )
        )
        containerView.setNeedsLayout()
        containerView.layoutIfNeeded()
    }

    /// 表示中のページの基準矩形を、器の View の4辺からの幅に直す。
    ///
    /// 基準矩形はページ自身の safe area の内側で、さらに可視領域からもはみ出さないよう
    /// 辺ごとに可視領域の余白以上にする。器がまだウィンドウに載っていないとき
    /// (提示前のサイズ確定) は問い合わせずに nil を返す。ページが得られなかったときは
    /// nil を返し、基準は可視領域に落ちる。
    /// - Parameter reportsUnresolved: ページが得られなかった理由を診断ログに出すか
    private func currentPageInsets(
        for layout: DialogLayout,
        in containerView: UIView,
        visibleAreaInsets: DialogEdgeInsets,
        reportsUnresolved: Bool
    ) -> DialogEdgeInsets? {
        guard layout.layoutArea == .currentPage, let window = containerView.window else { return nil }
        switch currentPageResolver.resolve(in: window) {
        case .resolved(let pageRectInWindow):
            let page = containerView.convert(pageRectInWindow, from: window)
            let bounds = containerView.bounds
            return DialogEdgeInsets(
                top: max(visibleAreaInsets.top, Double(page.minY - bounds.minY)),
                left: max(visibleAreaInsets.left, Double(page.minX - bounds.minX)),
                bottom: max(visibleAreaInsets.bottom, Double(bounds.maxY - page.maxY)),
                right: max(visibleAreaInsets.right, Double(bounds.maxX - page.maxX))
            )
        case .unresolved(let reasons):
            guard reportsUnresolved else { return nil }
            let message = DialogCurrentPageResolution.diagnosticMessage(reasons: reasons)
            currentPageDiagnostics.append(message)
            Self.logger.warning("\(message, privacy: .public)")
            return nil
        }
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
