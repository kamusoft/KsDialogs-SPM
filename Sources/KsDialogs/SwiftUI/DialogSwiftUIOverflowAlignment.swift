#if canImport(UIKit)
import Observation

/// ホストのルートで、安全領域の内側に収まらない中身を内側の辺へそろえる軸 (ios/ADR-0003)。
///
/// 軸ごとに、中身がはみ出していると判定したときだけ、器が付いた側 (物理の向き) を持つ。
/// nil の軸ではルートの包みは何もせず、中身は SwiftUI の標準どおりに置かれる。
@MainActor
@Observable
final class DialogSwiftUIOverflowAlignment {
    var horizontal: DialogAnchoredEdge?
    var vertical: DialogAnchoredEdge?
}
#endif
