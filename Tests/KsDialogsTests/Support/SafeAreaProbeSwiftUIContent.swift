#if canImport(UIKit)
import KsDialogs
import SwiftUI

/// 器の中で見えた安全領域と矩形を記録する SwiftUI の中身。
///
/// 大きさはモデルで決まる (可変・一部だけ縮む・固定)。`ignoresSafeArea` で一番外側に安全領域
/// (システムの領域) を無視する指定を付けた形にできる。`record` は無視する指定の内側にある一番外側の
/// View から見えた値、`innerRecord` はその内側の子から見えた値を記録する。`drawn` を渡すと、
/// 一番外側の View に重ねた UIView の目印で描かれた位置を読める。
struct SafeAreaProbeSwiftUIContent: View {
    let model: SwiftUISafeAreaProbeModel
    let record: SwiftUISafeAreaRecord
    var ignoresSafeArea = false
    /// 添付する静的メタ属性。nil なら何も添付せず、器の契約既定値に任せる。
    var options: DialogOptions? = DialogOptions(layoutArea: .window)
    var innerRecord: SwiftUISafeAreaRecord?
    var drawn: SwiftUIDrawnFrameProbe?

    var body: some View {
        if let options {
            recorded.ksDialogOptions(options)
        } else {
            recorded
        }
    }

    private var recorded: some View {
        sized
            .background {
                if let drawn {
                    SwiftUIDrawnFrameMarker(probe: drawn)
                }
            }
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                MainActor.assumeIsolated { record.record(insets: insets) }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                MainActor.assumeIsolated { record.record(frame: frame) }
            }
            .ignoresSafeArea(.container, edges: ignoresSafeArea ? .all : [])
    }

    /// 固定と可変を同じ frame の指定で表し、表示中に切り替えても中身が作り直されないようにする。
    private var sized: some View {
        let width = model.idealWidth
        let height = model.idealHeight
        let isFixed = model.isFixedSize
        return inner.frame(
            minWidth: isFixed ? width : nil,
            idealWidth: width,
            maxWidth: isFixed ? width : nil,
            minHeight: isFixed ? height : model.minHeight,
            idealHeight: height,
            maxHeight: isFixed ? height : nil
        )
    }

    private var inner: some View {
        Color.clear
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                MainActor.assumeIsolated { innerRecord?.record(insets: insets) }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                MainActor.assumeIsolated { innerRecord?.record(frame: frame) }
            }
    }
}
#endif
