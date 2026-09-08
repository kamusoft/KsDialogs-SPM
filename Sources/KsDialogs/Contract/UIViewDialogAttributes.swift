#if canImport(UIKit)
import ObjectiveC
import UIKit

/// ダイアログの中身になる View にメタ属性を添付する面 (core/ADR-0015)。
///
/// View の初期化時などに設定しておくと、その View をダイアログとして表示する器が
/// 初回のネイティブレイアウトパス完了時点の値を実効値として採用する。
/// 未設定の面は契約の既定値を意味する。
public extension UIView {
    /// この View をダイアログとして表示するときの静的メタ属性。
    var ksDialogOptions: DialogOptions? {
        get {
            objc_getAssociatedObject(self, DialogAttributeAssociationKeys.options) as? DialogOptions
        }
        set {
            objc_setAssociatedObject(
                self,
                DialogAttributeAssociationKeys.options,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    /// この View をダイアログとして表示するときの出入りの演出 (core/ADR-0017)。
    /// 指定しなかった側のフックには器の既定の演出が適用される。
    var ksDialogTransition: DialogTransition? {
        get {
            objc_getAssociatedObject(self, DialogAttributeAssociationKeys.transition)
                .flatMap { ($0 as? DialogTransitionBox)?.transition }
        }
        set {
            objc_setAssociatedObject(
                self,
                DialogAttributeAssociationKeys.transition,
                newValue.map(DialogTransitionBox.init),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    /// この View をダイアログとして表示するときの動的メタ属性。
    /// show の引数で placement を渡した場合は、そちらがこの値を置換する。
    var ksDialogPlacement: DialogPlacement? {
        get {
            objc_getAssociatedObject(self, DialogAttributeAssociationKeys.placement) as? DialogPlacement
        }
        set {
            objc_setAssociatedObject(
                self,
                DialogAttributeAssociationKeys.placement,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

/// 添付値を View に結び付けるための一意な鍵。
///
/// 鍵はアドレスの同一性だけが意味を持つ。静的変数のアドレスを借りると
/// メモリ排他規則に触れるため、この用途のためだけに確保した領域を使う。
/// 確保後に書き換えないので、複数スレッドから同時に読んでも安全である。
private enum DialogAttributeAssociationKeys {
    nonisolated(unsafe) static let options =
        UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    nonisolated(unsafe) static let placement =
        UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
    nonisolated(unsafe) static let transition =
        UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))
}

/// 添付面に載せるための、構造体を参照で運ぶ包み。
/// 添付の仕組みは参照型しか保持できないため、値の演出をこの箱に入れて結び付ける。
private final class DialogTransitionBox {
    let transition: DialogTransition

    init(_ transition: DialogTransition) {
        self.transition = transition
    }
}
#endif
