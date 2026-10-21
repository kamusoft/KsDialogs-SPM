#if canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI の中身を器が扱う内部表現へ変換する (core/ADR-0011)。
@MainActor
enum DialogSwiftUIHost {
    /// 中身を `UIHostingController` に載せ、添付値の受け取り口を重ねた内部表現を作る。
    /// ホストは器の child view controller として組み込まれ、閉鎖時に外される。
    static func makeContent<Content: View>(_ content: Content) -> DialogContent {
        let contentView = DialogSwiftUIContentView()
        let sink = DialogAttributeSupplySink()
        sink.contentView = contentView
        let safeAreaEdges = DialogSwiftUISafeAreaEdges()
        let overflowAlignment = DialogSwiftUIOverflowAlignment()
        let hostingController = UIHostingController(
            rootView: DialogSwiftUIRoot(
                content: content,
                sink: sink,
                safeAreaEdges: safeAreaEdges,
                overflowAlignment: overflowAlignment,
                onContentResize: { [weak contentView] in contentView?.hostedContentDidResize() }
            )
        )
        // 器の覆いと中身の見えは中身自身が決めるため、ホスト側の地色は持たせない。
        hostingController.view.backgroundColor = .clear
        // 中身が求める大きさの変化を知らせさせる。器へ伝える要求サイズは、ホストを敷く
        // `DialogSwiftUIContentView` がホストに問い合わせて求める (core/ADR-0009 の共通ケース表の入力になる)。
        hostingController.sizingOptions = [.preferredContentSize]
        // 中身へはシステムの領域 (ステータスバー・ホームインジケータ等) だけを標準の安全領域として渡し、
        // キーボードの領域は渡さない。どの軸の重なりを渡すかと、受け取った安全領域を要求サイズから
        // 引き戻すことは、ホストを敷く `DialogSwiftUIContentView` が受け持つ。
        hostingController.safeAreaRegions = .container
        // ここで敷く先は器から切り離された包みであり、ホストの View が器の View 階層に入るのは
        // 器がこの包みを載せる時点になる。器はそれを child への組み込みのあと・出現通知の前に行う。
        contentView.embed(hostingController, safeAreaEdges: safeAreaEdges, overflowAlignment: overflowAlignment)
        return DialogContent(view: contentView, host: hostingController)
    }
}

/// preference で届いた添付値を中身の View へ引き渡す口。
///
/// ホストの生成時点では中身の View が先に決まるため、参照は弱く持って循環を作らない。
@MainActor
final class DialogAttributeSupplySink {
    weak var contentView: DialogSwiftUIContentView?

    func supply(_ attachment: DialogAttributeAttachment) {
        contentView?.resolveAttributeSupply(attachment)
    }
}

/// 中身に添付値の受け取り口を重ね、器が重なりを渡さない辺の安全領域を無視させたホストのルート。
///
/// 中身は常に 1 つの frame で包む。中身が安全領域の内側に収まらない軸でだけ、その frame が
/// 「縮められる限り縮め、内側の辺にそろえる」働きをし、それ以外の軸では何もしない (大きさの指定を
/// 持たない)。はみ出すかどうかで包みを差し込んだり外したりすると中身が作り直されて状態を失うため、
/// 包み自体は常に置く。
struct DialogSwiftUIRoot<Content: View>: View {
    let content: Content
    let sink: DialogAttributeSupplySink
    let safeAreaEdges: DialogSwiftUISafeAreaEdges
    let overflowAlignment: DialogSwiftUIOverflowAlignment
    /// 中身が置かれた大きさが変わったときに呼ばれる。
    let onContentResize: @MainActor () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let horizontal = overflowAlignment.horizontal
        let vertical = overflowAlignment.vertical
        content
            .background {
                DialogSwiftUIContentLayoutReader(onResize: onContentResize)
            }
            .backgroundPreferenceValue(DialogAttributeAttachmentKey.self) { attachment in
                DialogAttributeSupplyReader(sink: sink, attachment: attachment)
            }
            .ignoresSafeArea(.container, edges: safeAreaEdges.ignored)
            // はみ出す軸では、包みが提案の大きさを取り、それより大きい中身を内側の辺から付いた側へ
            // はみ出させる。最小 0 が無いと包みが中身の大きさまで膨らみ、中身は安全領域の内側の中央に
            // 置かれたままになる。包みは内側の辺の安全領域を無視し、器の内側の辺まで届かせる
            // (器が窓いっぱいで内側の辺も安全領域に重なるとき、そこへそろえるため)。
            .frame(
                minWidth: horizontal == nil ? nil : 0,
                maxWidth: horizontal == nil ? nil : .infinity,
                minHeight: vertical == nil ? nil : 0,
                maxHeight: vertical == nil ? nil : .infinity,
                alignment: Alignment(
                    horizontal: Self.innerHorizontalAlignment(of: horizontal, layoutDirection: layoutDirection),
                    vertical: Self.innerVerticalAlignment(of: vertical)
                )
            )
            .ignoresSafeArea(
                .container,
                edges: Self.innerEdges(horizontal: horizontal, vertical: vertical, layoutDirection: layoutDirection)
            )
    }

    /// はみ出す軸の内側の辺を、書字方向に応じた SwiftUI の辺の集合で返す。
    private static func innerEdges(
        horizontal: DialogAnchoredEdge?,
        vertical: DialogAnchoredEdge?,
        layoutDirection: LayoutDirection
    ) -> Edge.Set {
        var edges: Edge.Set = []
        if let innerIsLeading = innerHorizontalEdgeIsLeading(of: horizontal, layoutDirection: layoutDirection) {
            edges.insert(innerIsLeading ? .leading : .trailing)
        }
        switch vertical {
        case .leadingEdge:
            edges.insert(.bottom)
        case .trailingEdge:
            edges.insert(.top)
        case nil:
            break
        }
        return edges
    }

    /// 水平の付いた側から、内側の辺へそろえる配置を求める。
    private static func innerHorizontalAlignment(
        of anchoredEdge: DialogAnchoredEdge?,
        layoutDirection: LayoutDirection
    ) -> HorizontalAlignment {
        switch innerHorizontalEdgeIsLeading(of: anchoredEdge, layoutDirection: layoutDirection) {
        case true?:
            return .leading
        case false?:
            return .trailing
        case nil:
            return .center
        }
    }

    /// 水平の内側の辺が、SwiftUI の leading の辺か。付いた側が無ければ nil。
    ///
    /// 付いた側は物理の向き (左 / 右) なので、書字方向を読んで SwiftUI の leading / trailing へ直す。
    /// 右から左の書字方向では leading が右になる。
    private static func innerHorizontalEdgeIsLeading(
        of anchoredEdge: DialogAnchoredEdge?,
        layoutDirection: LayoutDirection
    ) -> Bool? {
        guard let anchoredEdge else { return nil }
        let innerEdgeIsLeft = anchoredEdge == .trailingEdge
        let leftIsLeading = layoutDirection == .leftToRight
        return innerEdgeIsLeft == leftIsLeading
    }

    /// 垂直の付いた側から、内側の辺へそろえる配置を求める。上に付いたら下の辺、下に付いたら上の辺。
    private static func innerVerticalAlignment(of anchoredEdge: DialogAnchoredEdge?) -> VerticalAlignment {
        switch anchoredEdge {
        case .leadingEdge:
            return .bottom
        case .trailingEdge:
            return .top
        case nil:
            return .center
        }
    }
}

/// 添付値をホストへ引き渡すためだけの、見えも当たり判定も持たない中身。
///
/// SwiftUI の更新の中で `UIView` として実体化されるため、
/// 添付値の到達を器のレイアウトパスと同じ時間軸で捉えられる。
private struct DialogAttributeSupplyReader: UIViewRepresentable {
    let sink: DialogAttributeSupplySink
    let attachment: DialogAttributeAttachment

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        sink.supply(attachment)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        sink.supply(attachment)
    }
}
#endif
