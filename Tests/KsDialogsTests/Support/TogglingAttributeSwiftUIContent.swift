#if canImport(UIKit)
import SwiftUI

@testable import KsDialogs

/// 自分の状態変化で添付値を切り替える SwiftUI の中身。
/// 提示後に添付値が変わっても表示が追随しないこと (スナップショット契約) を観察するために使う。
struct TogglingAttributeSwiftUIContent: View {
    /// 添付値の切り替えを外から操作する箱。
    @MainActor
    final class Switch: ObservableObject {
        @Published var usesChangedAttributes = false
    }

    let contentSize: CGSize
    @ObservedObject var attributeSwitch: Switch
    let initialOptions: DialogOptions
    let initialPlacement: DialogPlacement
    let changedOptions: DialogOptions
    let changedPlacement: DialogPlacement

    var body: some View {
        Color.clear
            .frame(width: contentSize.width, height: contentSize.height)
            .ksDialogOptions(attributeSwitch.usesChangedAttributes ? changedOptions : initialOptions)
            .ksDialogPlacement(attributeSwitch.usesChangedAttributes ? changedPlacement : initialPlacement)
    }
}
#endif
