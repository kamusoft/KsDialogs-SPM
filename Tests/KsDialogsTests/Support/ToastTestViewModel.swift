#if canImport(UIKit)
import Foundation

@testable import KsDialogs

/// カスタム Toast の表示に使う素の ViewModel。
final class ToastTestViewModel: ToastViewModel {
    let message: String

    init(message: String = "カスタム Toast") {
        self.message = message
    }
}

/// configure から状態を設定できる ViewModel。型指定の表示の観察に使う。
/// 状態の変更は UI スレッドに限るため MainActor に閉じる。
@MainActor
final class ConfigurableToastTestViewModel: ToastViewModel {
    /// 中身の生成時に読まれる表題。configure で設定する。
    var title: String

    nonisolated init(title: String = "factory の既定") {
        self.title = title
    }
}

/// Toast レジストリに登録しない ViewModel。構成ミスの再現に使う。
final class UnregisteredToastTestViewModel: ToastViewModel {
    init() {}
}

/// 型消去された factory の受け取り型と食い違わせるための ViewModel。
/// 受理は通るが中身の実体化で失敗する経路 (受理後の失敗) の再現に使う。
final class MismatchedToastTestViewModel: ToastViewModel {
    init() {}
}

/// 中身の作り手が投げる失敗。受理後の失敗 (factory の例外) の再現に使う。
enum ToastTestContentFailure: Error {
    case cannotMakeContent
}
#endif
