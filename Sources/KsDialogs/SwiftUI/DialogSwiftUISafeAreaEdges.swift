#if canImport(UIKit)
import Observation
import SwiftUI

/// ホストのルートで無視させる安全領域の辺。
///
/// 器が重なりを渡さないと決めた軸の辺を持つ。ホストのルートはこの辺の安全領域を無視して
/// 中身を置くので、中身からはその辺の安全領域が 0 に見える。器が軸を指定するまでは全辺を持つ。
@MainActor
@Observable
final class DialogSwiftUISafeAreaEdges {
    var ignored: Edge.Set = .all
}
#endif
