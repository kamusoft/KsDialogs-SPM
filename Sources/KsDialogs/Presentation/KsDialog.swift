#if canImport(UIKit)
import SwiftUI
import UIKit

/// ダイアログ表示の契約。
/// 既定 singleton エントリ (`Dialog.shared`) と DI 注入のどちらからでも同じ契約で呼び出せる (core/ADR-0002)。
public protocol KsDialog: AnyObject, Sendable {
    /// ViewModel 型と View factory の紐付け。全ての入口が同じレジストリを共有する。
    var registry: DialogViewRegistry { get }

    /// ViewModel を渡してダイアログを表示し、結果を待つ。
    /// 結果型は ViewModel の宣言から導出され、completed(結果値) か cancelled のどちらかをちょうど1回返す。
    /// 提示先の指定は不要で、任意のスレッドから呼び出せる。
    /// 構成エラー (未登録の ViewModel 型など) では結果を返さずに `DialogError` を throw する。
    ///
    /// 表示できる画面 (前面でアクティブなシーンの key window) がまだ無いときは、失敗せずに
    /// 画面が現れるのを待ってから表示する。待つ時間に上限は無い。待っている間に呼び出し元の Task を
    /// キャンセルすると、一度も表示されずに cancelled を返す。待っている間に ViewModel が結果を
    /// 報告すると、表示されずにその結果を返す。待っているダイアログが複数あるときは、呼んだ順に
    /// 表示され、後から呼んだものが手前に重なる。
    ///
    /// show は呼び出し元の実行文脈のまま始まり、表示の処理だけを UI スレッド (MainActor) へ移して行う。
    /// そのため、UI スレッドから続けて呼んだ show は、呼んだ順のまま待ちの列に並ぶ。
    /// UI スレッド以外から呼んだ show の順は、呼び出しどうしの間で定まらない。
    ///
    /// `placement` を渡すと、中身の View に添付された placement を**まるごと置換**して配置を決める。
    /// nil のときは添付された値、添付もなければ契約の既定値になる (core/ADR-0015)。
    /// 静的メタ属性 (`DialogOptions`) は呼び出しごとに変えるものではないため、この面では渡せない。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?
    ) async throws -> DialogResult<ViewModel.Result>

    /// 登録せずに、その場で渡した factory の中身を表示する (core/ADR-0013)。
    ///
    /// factory の形も結果の返り方も登録経路とまったく同じで、`placement` の意味も変わらない。
    /// **レジストリの状態は一切変わらない** — 同じ ViewModel 型の登録があってもそれは使われず、
    /// 前後で登録内容も変化しない。同じ型のインライン表示を並行させても、
    /// factory・結果報告口・結果はそれぞれ独立する。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> UIView
    ) async throws -> DialogResult<ViewModel.Result>

    /// 登録せずに、その場で渡した SwiftUI の factory の中身を表示する (core/ADR-0013)。
    /// 従来 View 系のインライン show と同名で、factory の戻り値の型だけが違う。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel, Content: View>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> Content
    ) async throws -> DialogResult<ViewModel.Result>

    /// ViewModel の**型**を渡してダイアログを表示し、結果を待つ (core/ADR-0021)。
    ///
    /// ViewModel はレジストリに登録された ViewModel factory が作る。
    /// 実行順序は「ViewModel 生成 → configure の完了 → 中身の生成 → 提示」で固定されており、
    /// configure が設定した状態は中身の初期化から必ず読める。生成と configure は UI スレッド
    /// (MainActor) で実行される。
    ///
    /// ViewModel factory が未登録の場合と、生成・configure が失敗した場合は、結果を返さずに
    /// その失敗を throw する — 提示には進まず、cancelled 等の結果には化けない。
    /// notifier の供給・結果型の復元・`placement` の意味はインスタンス渡し show と同じである。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement?,
        configure: (@MainActor @Sendable (ViewModel) async throws -> Void)?
    ) async throws -> DialogResult<ViewModel.Result>
}

public extension KsDialog {
    /// 配置を中身の View への添付 (なければ契約の既定値) に委ねて表示する。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel>(
        _ viewModel: ViewModel
    ) async throws -> DialogResult<ViewModel.Result> {
        try await show(viewModel, placement: nil)
    }

    /// 配置を中身への添付 (なければ契約の既定値) に委ねてインライン表示する。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel>(
        _ viewModel: ViewModel,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> UIView
    ) async throws -> DialogResult<ViewModel.Result> {
        try await show(viewModel, placement: nil, factory: factory)
    }

    /// 配置を中身への添付 (なければ契約の既定値) に委ねて SwiftUI の中身をインライン表示する。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel, Content: View>(
        _ viewModel: ViewModel,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<ViewModel.Result>) throws -> Content
    ) async throws -> DialogResult<ViewModel.Result> {
        try await show(viewModel, placement: nil, factory: factory)
    }

    /// 登録済みの ViewModel factory に生成を任せ、configure なしで表示する。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type
    ) async throws -> DialogResult<ViewModel.Result> {
        try await show(viewModelType, placement: nil, configure: nil)
    }

    /// 登録済みの ViewModel factory に生成を任せ、configure で状態を整えてから表示する。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        configure: @escaping @MainActor @Sendable (ViewModel) async throws -> Void
    ) async throws -> DialogResult<ViewModel.Result> {
        try await show(viewModelType, placement: nil, configure: configure)
    }

    /// 登録済みの ViewModel factory に生成を任せ、配置を指定して表示する。
    nonisolated(nonsending) func show<ViewModel: DialogViewModel>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement?
    ) async throws -> DialogResult<ViewModel.Result> {
        try await show(viewModelType, placement: placement, configure: nil)
    }
}
#endif
