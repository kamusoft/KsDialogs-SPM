#if canImport(UIKit)
import KsDialogs
import SwiftUI

/// 折り返しを許す長い本文を持ち、見えた安全領域と矩形を記録する SwiftUI の中身。
///
/// 本文は一番外側の枠の中で左寄せに置き、記録はその枠で取る。本文そのものは安全領域の内側に
/// 置かれて自分の矩形が安全領域に掛からないため、本文の矩形から見える安全領域は常に 0 になる。
struct SafeAreaProbeWrappingText: View {
    let record: SwiftUISafeAreaRecord
    /// 一番外側に安全領域 (システムの領域) を無視する指定を付けるか。
    var ignoresSafeArea = false

    /// 1 行に並べると横長の窓の幅を超える長さの本文。
    static let text = String(repeating: "安全領域の内側で折り返す本文です。", count: 12)

    var body: some View {
        Text(Self.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets in
                MainActor.assumeIsolated { record.record(insets: insets) }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                MainActor.assumeIsolated { record.record(frame: frame) }
            }
            .ignoresSafeArea(.container, edges: ignoresSafeArea ? .all : [])
            .ksDialogOptions(DialogOptions(layoutArea: .window))
    }
}
#endif
