#if canImport(UIKit)
import Observation
import SwiftUI

/// 表示中に書き換えて、SwiftUI の中身が求める大きさを変えるためのモデル。
@MainActor
@Observable
final class MutableSwiftUIContentModel {
    var idealWidth: CGFloat
    var text: String

    init(idealWidth: CGFloat = 200, text: String = "OK") {
        self.idealWidth = idealWidth
        self.text = text
    }
}
#endif
