#if canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI の中身を器へ載せるための View。
///
/// 添付 DSL (`ksDialogOptions` / `ksDialogPlacement`) で供給された値を preference 経由で受け取り、
/// 自分自身の添付面へ書き戻す。これにより宣言的 UI の供給も従来 View 系とまったく同じ
/// 合成経路 (show 引数 > コンテンツ添付 > 契約既定値) に載る (core/ADR-0015)。
///
/// 供給が届くのはホストのレイアウトの中なので、器はこの View が持つ到達状態を見て
/// 実効値を固定する時点を決める。
///
/// ホストには、この View の safe area (器と窓の安全領域の重なり) のうち、器が指定した軸の分だけを
/// SwiftUI 標準の安全領域として渡す。ホストは受け取った安全領域を自分の求めるサイズへ足すため、
/// 器へ伝える要求サイズはそこから安全領域を引き戻した値にする。これで安全領域をいくつ受け取っても
/// 器の大きさは変わらず、端に付けた中身が器の内側で安全領域を避けるだけになる。
///
/// 窓全体を基準に片側の端へ付けた軸で、中身が安全領域の内側に収まらない (縮みきれない) ときは、
/// ホストのルートの包みで中身を内側の辺にそろえ、器いっぱいまで使って置かせる。
@MainActor
final class DialogSwiftUIContentView: UIView, DialogAttributeSupplyProbe, DialogContentSafeAreaRelay,
    DialogContentWidthLimitReceiver {
    private(set) var hasResolvedAttributeSupply = false

    /// 重なりをホストへ渡す軸。器が軸を指定するまでは、どちらの軸も渡さない。
    private var relaysHorizontalSafeArea = false
    private var relaysVerticalSafeArea = false

    private weak var host: UIViewController?

    /// ホストのルートで無視させる辺。渡さない軸の辺を持たせる。
    private var safeAreaEdges: DialogSwiftUISafeAreaEdges?

    /// ホストのルートで、収まらない中身を内側の辺へそろえる軸。
    private var overflowAlignment: DialogSwiftUIOverflowAlignment?

    /// 窓全体を基準に片側の端へ付けた軸の、器が付いた側。器が指定するまではどちらの軸も nil。
    private var anchoredHorizontalEdge: DialogAnchoredEdge?
    private var anchoredVerticalEdge: DialogAnchoredEdge?

    /// 最後にはみ出しを判定したときの入力。これが変わるまで判定を保つ。
    private var overflowInputs: OverflowInputs?

    /// 中身が置き直されたため、はみ出しを次のレイアウトパスで測り直すか。
    private var needsOverflowRecheck = false

    /// ルートの包みの変化をホストへ反映している最中か。
    private var isApplyingOverflowAlignment = false

    /// 器から最後に知らされた、幅を中身に委ねた軸の上限。
    private var notifiedWidthLimit: CGFloat?

    /// ホストが求める大きさの変化を知らせる監視。
    private var preferredSizeObservation: NSKeyValueObservation?

    /// 最後に器へ伝えた要求サイズ。ホスト側の変化を器へ伝え直すかの判定に使う。
    private var reportedContentSize: CGSize?

    /// 要求サイズを求めるときに中身へ提案する幅。nil なら幅を提案せず、理想の幅で求める。
    /// 器が要求サイズと違う幅で置いたときに、その置かれた幅になる。中身の理想の大きさが変わったら
    /// nil に戻し、理想の幅から求め直す。
    private var proposedWidth: CGFloat?

    /// 最後に確かめた中身の理想の大きさ。ホストが求める大きさの変化が、中身の理想の大きさ
    /// そのものの変化かを見分けるのに使う。
    private var lastIdealSize: CGSize?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("This View does not support instantiation from a storyboard.")
    }

    /// 中身が求める大きさ。ホストが安全領域を受け取っていないときに求める大きさと同じ値になる。
    ///
    /// 中身の理想の大きさが変わった直後は、幅を提案せずに理想の幅で求める。器が要求サイズと違う幅で
    /// 置いた後は、置かれた幅を幅の提案にして、その幅で折り返したときの大きさを求める。
    /// 高さは常に提案しない。
    override var intrinsicContentSize: CGSize {
        guard host != nil else { return super.intrinsicContentSize }
        return fittingSize(proposedWidth: proposedWidth)
    }

    /// ホストに大きさを問い合わせ、ホストが足した安全領域の分を引いた大きさを返す。
    ///
    /// ホストは自分の View の safe area を、ルートが無視する辺の分も含めて中身の外側に足して答えるので、
    /// 幅の提案にはその分を足して渡し、答えからその分を引く。
    /// - Parameter proposedWidth: 中身に提案する幅。nil なら幅も提案しない
    private func fittingSize(proposedWidth: CGFloat?) -> CGSize {
        guard let hostedView = host?.view else { return .zero }
        let hostedInsets = hostedView.safeAreaInsets
        let horizontalInsets = hostedInsets.left + hostedInsets.right
        let verticalInsets = hostedInsets.top + hostedInsets.bottom
        // ホストは際限のない大きさの提案を「提案なし」として扱う。
        let unproposed = CGFloat.greatestFiniteMagnitude
        let proposal = CGSize(
            width: proposedWidth.map { $0 + horizontalInsets } ?? unproposed,
            height: unproposed
        )
        let fitting = hostedView.sizeThatFits(proposal)
        return CGSize(
            width: max(0, fitting.width - horizontalInsets),
            height: max(0, fitting.height - verticalInsets)
        )
    }

    func relaySafeArea(horizontal: Bool, vertical: Bool) {
        guard horizontal != relaysHorizontalSafeArea || vertical != relaysVerticalSafeArea else { return }
        relaysHorizontalSafeArea = horizontal
        relaysVerticalSafeArea = vertical
        var ignored: Edge.Set = []
        if !horizontal { ignored.formUnion(.horizontal) }
        if !vertical { ignored.formUnion(.vertical) }
        safeAreaEdges?.ignored = ignored
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func anchorEdges(horizontal: DialogAnchoredEdge?, vertical: DialogAnchoredEdge?) {
        guard horizontal != anchoredHorizontalEdge || vertical != anchoredVerticalEdge else { return }
        anchoredHorizontalEdge = horizontal
        anchoredVerticalEdge = vertical
        setNeedsLayout()
    }

    /// 上限が前に知らされた値より広がったときだけ、覚えた幅を捨てて理想の幅から求め直す。
    ///
    /// 覚えた幅と上限を比べると、上限よりわずかに狭い幅で落ち着いた本文で、同じ上限が知らされる
    /// たびに求め直しを繰り返してしまうため、比べる相手は前に知らされた上限にする。
    func contentSizedWidthLimitDidChange(_ limit: CGFloat?) {
        let previousLimit = notifiedWidthLimit
        notifiedWidthLimit = limit
        guard let limit, let previousLimit, limit > previousLimit + Self.sizeTolerance else { return }
        proposedWidth = nil
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    /// ホストの内容サイズは器の大きさを決めない優先度にしてあるため、ホストが求めるサイズが
    /// 変わっても、そのままでは器へ届かない。レイアウトのたびに要求サイズを比べ、変わっていれば伝え直す。
    ///
    /// 器が前に伝えた要求サイズと違う幅で置いた (有効領域で頭打ちにした・全面に広げた・窓が変わって
    /// 広げた) ときは、置かれた幅で折り返した大きさを伝え直す。器が前に伝えた幅どおりに置いている間は
    /// 提案する幅を変えないので、置き直すたびに幅が動き続けることはない。
    override func layoutSubviews() {
        super.layoutSubviews()
        if lastIdealSize == nil, bounds.width > 0 {
            lastIdealSize = fittingSize(proposedWidth: nil)
        }
        let requestedWidth = (reportedContentSize ?? intrinsicContentSize).width
        if bounds.width > 0, !Self.isClose(bounds.width, requestedWidth) {
            proposedWidth = bounds.width
        }
        let contentSize = intrinsicContentSize
        if contentSize != reportedContentSize {
            reportedContentSize = contentSize
            invalidateIntrinsicContentSize()
            // 器の矩形が変わらなかったときにも、伝え直した要求サイズに器が応えたかを次のパスで見る。
            setNeedsLayout()
        }
        updateOverflowAlignment()
    }

    /// はみ出しの判定に使う入力。どれかが変わったときだけ判定し直す。
    private struct OverflowInputs: Equatable {
        let size: CGSize
        let idealSize: CGSize?
        let safeAreaInsets: UIEdgeInsets
        let horizontal: DialogAnchoredEdge?
        let vertical: DialogAnchoredEdge?
    }

    /// 片側の端に付けた軸ごとに、中身が安全領域の内側に収まるかを判定し、ルートの包みへ伝える。
    ///
    /// 包みが効いている間は、包みが中身を安全領域の内側の大きさに収めて見せるため、はみ出しを
    /// 測れない。そこで判定は包みを外した状態で行い、器の大きさ・中身の理想の大きさ・中身が受け取る
    /// 安全領域・付いた側のどれかが変わるまで保つ。判定は同じレイアウトパスの中で行い、
    /// 包みを外した状態は描画されない。
    ///
    /// それらが変わらなくても、中身が置き直された (縮められる範囲が変わった) ときは、包みが
    /// 効いている軸も含めて同じように包みを外して測り直す。縮められる範囲が戻って収まるように
    /// なった軸では、ここで包みが外れる。
    private func updateOverflowAlignment() {
        let needsRecheck = needsOverflowRecheck
        needsOverflowRecheck = false
        guard let overflowAlignment, let hostedView = host?.view, bounds.width > 0, bounds.height > 0 else { return }
        let inputs = OverflowInputs(
            size: bounds.size,
            idealSize: lastIdealSize,
            safeAreaInsets: hostedView.safeAreaInsets,
            horizontal: anchoredHorizontalEdge,
            vertical: anchoredVerticalEdge
        )
        guard inputs != overflowInputs || needsRecheck else { return }
        overflowInputs = inputs
        applyOverflowAlignment(horizontal: nil, vertical: nil, to: overflowAlignment, hostedView: hostedView)
        guard inputs.horizontal != nil || inputs.vertical != nil else { return }
        let overflow = overflowingEdges(inputs)
        applyOverflowAlignment(
            horizontal: overflow.horizontal,
            vertical: overflow.vertical,
            to: overflowAlignment,
            hostedView: hostedView
        )
    }

    /// 中身に安全領域の内側の大きさを提案し、はみ出す軸ごとに付いた側を返す。
    private func overflowingEdges(_ inputs: OverflowInputs) -> (horizontal: DialogAnchoredEdge?, vertical: DialogAnchoredEdge?) {
        let available = availableSize(insets: inputs.safeAreaInsets)
        let measured = fittingSize(in: available, insets: inputs.safeAreaInsets)
        return (
            horizontal: measured.width > available.width + Self.sizeTolerance ? inputs.horizontal : nil,
            vertical: measured.height > available.height + Self.sizeTolerance ? inputs.vertical : nil
        )
    }

    /// 包みの指定が今と違うときだけ書き換え、このレイアウトパスの中でホストへ反映させる。
    ///
    /// 同じ値の書き込みでもホストのルートは評価し直されるため、変わらないときは書かない。
    /// 反映の間に中身が置き直された知らせは、包み自身の変化によるものなので受け取らない。
    private func applyOverflowAlignment(
        horizontal: DialogAnchoredEdge?,
        vertical: DialogAnchoredEdge?,
        to overflowAlignment: DialogSwiftUIOverflowAlignment,
        hostedView: UIView
    ) {
        guard overflowAlignment.horizontal != horizontal || overflowAlignment.vertical != vertical else { return }
        if overflowAlignment.horizontal != horizontal {
            overflowAlignment.horizontal = horizontal
        }
        if overflowAlignment.vertical != vertical {
            overflowAlignment.vertical = vertical
        }
        isApplyingOverflowAlignment = true
        Self.flushLayout(of: hostedView)
        isApplyingOverflowAlignment = false
    }

    /// 中身が置かれた大きさが変わったときに呼ばれる。
    ///
    /// 片側の端に付けた軸があれば、包みが効いているかによらず、次のレイアウトパスでその軸の
    /// はみ出しを包みを外して測り直す。包み自身の変化で中身が置き直された知らせは受け取らない。
    func hostedContentDidResize() {
        guard !isApplyingOverflowAlignment, overflowAlignment != nil else { return }
        guard anchoredHorizontalEdge != nil || anchoredVerticalEdge != nil else { return }
        needsOverflowRecheck = true
        setNeedsLayout()
    }

    /// ルートの包みの変化を、このレイアウトパスの中でホストへ反映させる。
    /// 反映を次の更新まで待つと、包みを外した状態で測れず、外した状態が 1 度描かれてしまう。
    private static func flushLayout(of hostedView: UIView) {
        hostedView.setNeedsLayout()
        hostedView.layoutIfNeeded()
    }

    /// 中身が実際に提案される大きさ。重なりを渡す軸では、器から安全領域を除いた大きさになる。
    private func availableSize(insets: UIEdgeInsets) -> CGSize {
        CGSize(
            width: max(0, bounds.width - (relaysHorizontalSafeArea ? insets.left + insets.right : 0)),
            height: max(0, bounds.height - (relaysVerticalSafeArea ? insets.top + insets.bottom : 0))
        )
    }

    /// 中身に `size` を提案したときに中身が求める大きさ。
    ///
    /// ホストは提案から自分の safe area を引いて中身へ渡し、答えにその分を足して返すので、
    /// 提案には safe area を足して渡し、答えから引く。
    private func fittingSize(in size: CGSize, insets: UIEdgeInsets) -> CGSize {
        guard let hostedView = host?.view else { return .zero }
        let horizontalInsets = insets.left + insets.right
        let verticalInsets = insets.top + insets.bottom
        let fitting = hostedView.sizeThatFits(
            CGSize(width: size.width + horizontalInsets, height: size.height + verticalInsets)
        )
        return CGSize(
            width: max(0, fitting.width - horizontalInsets),
            height: max(0, fitting.height - verticalInsets)
        )
    }

    /// 大きさを同じと見なすときの許容誤差 (画素の丸めと、安全領域を引く計算の誤差の分)。
    private static let sizeTolerance: CGFloat = 0.5

    private static func isClose(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= sizeTolerance
    }

    /// ホストが求める大きさが変わったときに呼ばれる。
    ///
    /// ホストの `preferredContentSize` は、置かれた幅や受け取った安全領域が変わったときにも変わる。
    /// 提案する幅を捨てて理想の幅から求め直すのは、中身の理想の大きさそのものが変わったときだけにする。
    private func contentPreferredSizeDidChange() {
        let idealSize = fittingSize(proposedWidth: nil)
        if let lastIdealSize,
           !Self.isClose(lastIdealSize.width, idealSize.width) || !Self.isClose(lastIdealSize.height, idealSize.height) {
            proposedWidth = nil
        }
        lastIdealSize = idealSize
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    /// ホストの View を全面に敷く。中身が要求するサイズはこの View の内容サイズとして器へ伝わる。
    ///
    /// ホストが求める大きさの変化 (中身の文言や状態の変化) は、ホストの `preferredContentSize` の
    /// 更新で知り、理想の幅から要求サイズを求め直す。
    func embed(
        _ host: UIViewController,
        safeAreaEdges: DialogSwiftUISafeAreaEdges,
        overflowAlignment: DialogSwiftUIOverflowAlignment
    ) {
        self.host = host
        self.safeAreaEdges = safeAreaEdges
        self.overflowAlignment = overflowAlignment
        let hostedView: UIView = host.view
        // ホスト自身の内容サイズ (安全領域を足した大きさ) が器の大きさを押し広げないよう、
        // 器の大きさはこの View の内容サイズだけで決める。
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            hostedView.setContentHuggingPriority(.fittingSizeLevel, for: axis)
            hostedView.setContentCompressionResistancePriority(.fittingSizeLevel, for: axis)
        }
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostedView.leftAnchor.constraint(equalTo: leftAnchor),
            hostedView.rightAnchor.constraint(equalTo: rightAnchor)
        ])
        preferredSizeObservation = host.observe(\.preferredContentSize) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.contentPreferredSizeDidChange()
            }
        }
    }

    /// preference から届いた添付値を自分の添付面へ書き戻す。
    func resolveAttributeSupply(_ attachment: DialogAttributeAttachment) {
        hasResolvedAttributeSupply = true
        ksDialogOptions = attachment.options
        ksDialogPlacement = attachment.placement
        ksDialogTransition = attachment.transition
    }
}
#endif
