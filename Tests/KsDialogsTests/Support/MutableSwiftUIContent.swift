#if canImport(UIKit)
import KsDialogs
import SwiftUI

/// モデルの書き換えで求める大きさが変わる SwiftUI の中身。
///
/// `.idealWidth` は大きさが可変で理想の幅だけをモデルから取る形、`.text` はモデルの文言を
/// 1 つの `Text` で出す形。`options` が nil なら何も添付せず、器の契約既定値に任せる。
struct MutableSwiftUIContent: View {
    enum Kind: Sendable {
        case idealWidth
        case text
    }

    let model: MutableSwiftUIContentModel
    let kind: Kind
    var options: DialogOptions?

    var body: some View {
        if let options {
            shaped.ksDialogOptions(options)
        } else {
            shaped
        }
    }

    @ViewBuilder
    private var shaped: some View {
        switch kind {
        case .idealWidth:
            Color.clear.frame(idealWidth: model.idealWidth, idealHeight: 100)
        case .text:
            Text(model.text)
        }
    }
}
#endif
