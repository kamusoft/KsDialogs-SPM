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
        let hostingController = UIHostingController(
            rootView: DialogSwiftUIRoot(content: content, sink: sink, safeAreaEdges: safeAreaEdges)
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
        contentView.embed(hostingController, safeAreaEdges: safeAreaEdges)
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
struct DialogSwiftUIRoot<Content: View>: View {
    let content: Content
    let sink: DialogAttributeSupplySink
    let safeAreaEdges: DialogSwiftUISafeAreaEdges

    var body: some View {
        content
            .backgroundPreferenceValue(DialogAttributeAttachmentKey.self) { attachment in
                DialogAttributeSupplyReader(sink: sink, attachment: attachment)
            }
            .ignoresSafeArea(.container, edges: safeAreaEdges.ignored)
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
