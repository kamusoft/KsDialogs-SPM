#if canImport(UIKit)
import KsDialogs
import SwiftUI

/// 器の中で見えた安全領域と矩形を記録する SwiftUI の中身。
///
/// 既定では大きさが可変で、モデルの理想の大きさを求める。`isFixedSize` で固定サイズの指定に、
/// `ignoresSafeArea` で一番外側に安全領域 (システムの領域) を無視する指定を付けた形にできる。
/// 記録するのは、無視する指定の内側にある View から見えた値である。
struct SafeAreaProbeSwiftUIContent: View {
    let model: SwiftUISafeAreaProbeModel
    let record: SwiftUISafeAreaRecord
    var isFixedSize = false
    var ignoresSafeArea = false
    /// 添付する静的メタ属性。nil なら何も添付せず、器の契約既定値に任せる。
    var options: DialogOptions? = DialogOptions(layoutArea: .window)

    var body: some View {
        if let options {
            recorded.ksDialogOptions(options)
        } else {
            recorded
        }
    }

    private var recorded: some View {
        sized
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                MainActor.assumeIsolated { record.record(insets: insets) }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                MainActor.assumeIsolated { record.record(frame: frame) }
            }
            .ignoresSafeArea(.container, edges: ignoresSafeArea ? .all : [])
    }

    @ViewBuilder
    private var sized: some View {
        if isFixedSize {
            Color.clear.frame(width: model.idealWidth, height: model.idealHeight)
        } else {
            Color.clear.frame(idealWidth: model.idealWidth, idealHeight: model.idealHeight)
        }
    }
}
#endif
