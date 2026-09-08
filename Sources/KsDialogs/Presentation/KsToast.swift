#if canImport(UIKit)
import SwiftUI
import UIKit

/// Toast 表示の契約。
/// 既定 singleton エントリ (`Toast.shared`) と DI 注入のどちらからでも同じ契約で呼び出せる
/// (core/ADR-0002)。どちらの入口から呼んでもレジストリと一括設定は 1 プロセスで共有される。
///
/// Toast は fire-and-forget の表示である (core/ADR-0031)。show は戻り値を持たず、
/// 表示の終了を待つ手段も、閉じる・書き換える手段も契約に無い。消滅の契機は duration の経過だけで、
/// 表示中はいかなる入力も奪わない。
///
/// すべての呼び出しは任意のスレッドから行え、内部で UI スレッドへ移して受理順に直列化される。
public protocol KsToast: AnyObject, Sendable {
    /// カスタム Toast の ViewModel 型と View factory の紐付け。
    /// Dialog / Loading のレジストリとは独立している。
    var registry: ToastViewRegistry { get }

    /// Toast の一括設定 (core/ADR-0032)。各表示の受理時に読まれる。
    var style: ToastStyle { get set }

    /// デフォルト View でメッセージを表示する。
    ///
    /// 表示は受理された時点から数え、`duration` の経過で自動的に消える。
    /// メッセージの内容は制限しない — 空文字は内容が空のまま表示され、長文は複数行に折り返す。
    /// - Parameters:
    ///   - message: 表示する文言
    ///   - duration: 表示するミリ秒。nil なら `ToastStyle` の既定 duration。0 以下は既定へ丸める
    ///   - placement: 配置。nil なら `ToastStyle` のアプリ既定配置、それも無ければ契約の既定値
    func show(message: String, duration: Int?, placement: DialogPlacement?)

    /// 登録済みのカスタム Toast View を表示する (core/ADR-0029 レジストリ経路)。
    ///
    /// 未登録の ViewModel 型は構成ミスとして呼び出し時点で失敗し、表示は行われない。
    func show<ViewModel: ToastViewModel>(
        _ viewModel: ViewModel,
        duration: Int?,
        placement: DialogPlacement?
    ) throws

    /// 登録せずに、その場で渡した factory の中身をカスタム Toast として表示する (core/ADR-0013)。
    ///
    /// **レジストリの状態は一切変わらない** — 同じ ViewModel 型の登録があってもそれは使われず、
    /// 前後で登録内容も変化しない。
    func show<ViewModel: ToastViewModel>(
        _ viewModel: ViewModel,
        duration: Int?,
        placement: DialogPlacement?,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) throws

    /// 登録せずに、その場で渡した SwiftUI の factory の中身を表示する (core/ADR-0013)。
    /// 従来 View 系のインライン表示と同名で、factory の戻り値の型だけが違う。
    func show<ViewModel: ToastViewModel, Content: View>(
        _ viewModel: ViewModel,
        duration: Int?,
        placement: DialogPlacement?,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) throws

    /// ViewModel の**型**を渡して、登録済みのカスタム Toast View を表示する。
    ///
    /// ViewModel はレジストリに登録された ViewModel factory が作る。
    /// 実行順序は「ViewModel 生成 → configure の完了 → 中身の生成 → 表示」で固定されており、
    /// configure が設定した状態は中身の初期化から必ず読める。
    /// 生成と configure は UI スレッドで受理順に実行される。
    ///
    /// ViewModel factory が未登録の場合は構成ミスとして呼び出し時点で失敗し、表示は行われない。
    /// 生成と configure の失敗は呼び出しが戻った後に起きるため呼び出し元へは返らず、
    /// その表示1枚だけが破棄される (他の表示と後続の表示には影響しない)。
    func show<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        duration: Int?,
        placement: DialogPlacement?,
        configure: (@MainActor @Sendable (ViewModel) throws -> Void)?
    ) throws
}

public extension KsToast {
    /// duration も配置も既定に委ねてデフォルト View で表示する。
    func show(message: String) {
        show(message: message, duration: nil, placement: nil)
    }

    /// 配置を既定に委ねてデフォルト View で表示する。
    func show(message: String, duration: Int?) {
        show(message: message, duration: duration, placement: nil)
    }

    /// duration も配置も既定に委ねて登録済みのカスタム Toast を表示する。
    func show<ViewModel: ToastViewModel>(_ viewModel: ViewModel) throws {
        try show(viewModel, duration: nil, placement: nil)
    }

    /// 配置を View への添付 (なければ既定) に委ねて登録済みのカスタム Toast を表示する。
    func show<ViewModel: ToastViewModel>(_ viewModel: ViewModel, duration: Int?) throws {
        try show(viewModel, duration: duration, placement: nil)
    }

    /// duration も配置も既定に委ねてインライン表示する。
    func show<ViewModel: ToastViewModel>(
        _ viewModel: ViewModel,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) throws {
        try show(viewModel, duration: nil, placement: nil, factory: factory)
    }

    /// duration も配置も既定に委ねて SwiftUI の中身をインライン表示する。
    func show<ViewModel: ToastViewModel, Content: View>(
        _ viewModel: ViewModel,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) throws {
        try show(viewModel, duration: nil, placement: nil, factory: factory)
    }

    /// 登録済みの ViewModel factory に生成を任せ、configure なしで表示する。
    func show<ViewModel: ToastViewModel>(_ viewModelType: ViewModel.Type) throws {
        try show(viewModelType, duration: nil, placement: nil, configure: nil)
    }

    /// 登録済みの ViewModel factory に生成を任せ、configure で状態を整えてから表示する。
    func show<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        configure: @escaping @MainActor @Sendable (ViewModel) throws -> Void
    ) throws {
        try show(viewModelType, duration: nil, placement: nil, configure: configure)
    }

    /// 登録済みの ViewModel factory に生成を任せ、duration を指定して表示する。
    func show<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        duration: Int?
    ) throws {
        try show(viewModelType, duration: duration, placement: nil, configure: nil)
    }

    /// 登録済みの ViewModel factory に生成を任せ、duration を指定して configure で状態を整えてから表示する。
    func show<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        duration: Int?,
        configure: @escaping @MainActor @Sendable (ViewModel) throws -> Void
    ) throws {
        try show(viewModelType, duration: duration, placement: nil, configure: configure)
    }

    /// 登録済みの ViewModel factory に生成を任せ、duration と配置を指定して表示する。
    func show<ViewModel: ToastViewModel>(
        _ viewModelType: ViewModel.Type,
        duration: Int?,
        placement: DialogPlacement?
    ) throws {
        try show(viewModelType, duration: duration, placement: placement, configure: nil)
    }
}
#endif
