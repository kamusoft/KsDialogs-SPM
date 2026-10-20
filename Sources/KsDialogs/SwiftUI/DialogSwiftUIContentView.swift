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
@MainActor
final class DialogSwiftUIContentView: UIView, DialogAttributeSupplyProbe, DialogContentSafeAreaRelay {
    private(set) var hasResolvedAttributeSupply = false

    /// 重なりをホストへ渡す軸。器が軸を指定するまでは、どちらの軸も渡さない。
    private var relaysHorizontalSafeArea = false
    private var relaysVerticalSafeArea = false

    private weak var host: UIViewController?

    /// ホストのルートで無視させる辺。渡さない軸の辺を持たせる。
    private var safeAreaEdges: DialogSwiftUISafeAreaEdges?

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
    func embed(_ host: UIViewController, safeAreaEdges: DialogSwiftUISafeAreaEdges) {
        self.host = host
        self.safeAreaEdges = safeAreaEdges
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
