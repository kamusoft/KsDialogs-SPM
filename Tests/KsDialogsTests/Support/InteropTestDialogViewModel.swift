import Foundation

@testable import KsDialogs

/// ObjC 互換面から扱う ViewModel。
/// 委譲元はクラスオブジェクトをキーにするため、ObjC から見えるクラスとして定義する。
@objc(KSDInteropTestDialogViewModel)
final class InteropTestDialogViewModel: NSObject, DialogViewModel {
    typealias Result = Bool

    let message: String

    init(message: String) {
        self.message = message
        super.init()
    }
}
