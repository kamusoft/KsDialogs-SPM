import Foundation

/// ObjC のクラスとして見える共有コードの ViewModel を模した検証用の型。
///
/// KMP 共有コードで定義した ViewModel は、iOS では ObjC のクラスとして Swift 側に現れる。
/// 紐付けと解決がその形の実例でも成り立つことを確かめるために使う。
@objc(KSDObjCSharedTestDialogViewModel)
final class ObjCSharedTestDialogViewModel: NSObject {
    let message: String

    init(message: String) {
        self.message = message
        super.init()
    }
}
