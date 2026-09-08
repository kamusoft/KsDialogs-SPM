#if canImport(UIKit)
import SwiftUI
import UIKit

/// ローディング表示の契約。
/// 既定 singleton エントリ (`Loading.shared`) と DI 注入のどちらからでも同じ契約で呼び出せる
/// (core/ADR-0002)。どちらの入口から呼んでも表示は 1 プロセスに 1 つで、合流状態を共有する。
///
/// すべての呼び出しは任意のスレッドから行え、内部で UI スレッドへ移して受理順に直列化される。
public protocol KsLoading: AnyObject, Sendable {
    /// カスタム Loading の ViewModel 型と View factory の紐付け。Dialog のレジストリとは独立している。
    var registry: LoadingViewRegistry { get }

    /// 既定ローディングの見た目の設定 (core/ADR-0023)。各表示の開始時に読まれる。
    var style: LoadingStyle { get set }

    /// 既定ローディングの器メタ属性。利用者が属性を添付する View を持たない既定ローディングでは、
    /// これがコンテンツへの添付の代わりになる。各表示の開始時に読まれる。
    /// `isCanceledOnTouchOutside` は Loading では常に無効で、設定しても効かない (core/ADR-0022)。
    var options: DialogOptions { get set }

    /// 既定ローディングを表示し、合流1件を開始する。
    ///
    /// 対応する終了は `hide()` だけである (合流数によらず即閉じる)。
    /// 戻るのは操作ブロックが有効になった時点で、入りの演出の完了は待たない。
    /// 既に表示中なら1つの表示に合流し、コンテンツは最初の開始のものが維持される (core/ADR-0024)。
    /// - Parameters:
    ///   - message: 表示するメッセージ。nil ならスタイルの既定メッセージ
    ///   - placement: 配置。nil なら契約の既定値 (core/ADR-0015)
    func show(message: String?, placement: DialogPlacement?) async

    /// 登録済みのカスタム Loading View を表示し、合流1件を開始する。
    ///
    /// 未登録の ViewModel 型は構成ミスとして失敗し、表示は行われない。
    func show<ViewModel: LoadingViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?
    ) async throws

    /// 登録せずに、その場で渡した factory の中身をカスタム Loading として表示する (core/ADR-0013)。
    ///
    /// factory の形も合流の数え方も登録経路とまったく同じで、`placement` の意味も変わらない。
    /// **レジストリの状態は一切変わらない** — 同じ ViewModel 型の登録があってもそれは使われず、
    /// 前後で登録内容も変化しない。
    func show<ViewModel: LoadingViewModel>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) async throws

    /// 登録せずに、その場で渡した SwiftUI の factory の中身を表示する (core/ADR-0013)。
    /// 従来 View 系のインライン表示と同名で、factory の戻り値の型だけが違う。
    func show<ViewModel: LoadingViewModel, Content: View>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) async throws

    /// ViewModel の**型**を渡して、登録済みのカスタム Loading View を表示する。
    ///
    /// ViewModel はレジストリに登録された ViewModel factory が作る。
    /// 実行順序は「ViewModel 生成 → configure の完了 → 進捗の受け口の紐付け → 中身の生成 → 表示」で
    /// 固定されており、configure が設定した状態は中身の初期化から必ず読める。
    /// 生成と configure は UI スレッドで実行される。
    ///
    /// ViewModel factory が未登録の場合と、生成・configure が失敗した場合は、表示に進まずに
    /// その失敗が呼び出し元へ伝わり、合流1件としても数えない。
    /// 合流・置き場所・進捗転送の意味はインスタンスを渡す表示と同じである。
    func show<ViewModel: LoadingViewModel>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement?,
        configure: (@MainActor @Sendable (ViewModel) async throws -> Void)?
    ) async throws

    /// 表示を閉じる。合流数によらず即座に閉じ、走行中の処理には干渉しない (core/ADR-0024)。
    /// 出の演出と器の撤去が完了してから戻る。表示していなければ何も起こらない。
    func hide() async

    /// 表示中のメッセージを更新する。合流には関与しない (対応する終了は要らない)。
    /// 既定ローディングを表示している間だけ効き、非表示中とカスタム View 表示中は何も起こらない。
    func setMessage(_ message: String?) async

    /// 既定ローディングを表示したまま処理を実行し、その戻り値を返す。
    ///
    /// 合流1件の開始と終了が処理の開始・完了に対応する。処理は表示状態によらず必ず実行され、
    /// 失敗 (例外・キャンセル) も合流1件の終了として数えたうえで呼び出し元へ伝播する。
    /// 合流最後の1件なら器の撤去まで待ってから戻り、そうでなければ処理の完了時点で戻る。
    /// - Parameter action: 実行する処理。引数の報告口へ 0〜1 の進捗を報告できる (任意スレッド可)
    func start<T: Sendable>(
        message: String?,
        placement: DialogPlacement?,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T

    /// 登録済みのカスタム Loading View を表示したまま処理を実行し、その戻り値を返す。
    ///
    /// 未登録の ViewModel 型は構成ミスとして失敗し、処理は実行されない (fail-fast)。
    func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T

    /// 登録せずに、その場で渡した factory の中身を表示したまま処理を実行する (core/ADR-0013)。
    /// レジストリの状態は一切変わらない。
    func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T

    /// 登録せずに、その場で渡した SwiftUI の factory の中身を表示したまま処理を実行する
    /// (core/ADR-0013)。従来 View 系のインライン実行と同名で、factory の戻り値の型だけが違う。
    func start<ViewModel: LoadingViewModel, Content: View, T: Sendable>(
        _ viewModel: ViewModel,
        placement: DialogPlacement?,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T

    /// ViewModel の**型**を渡して、登録済みのカスタム Loading View を表示したまま処理を実行する。
    ///
    /// ViewModel の生成・configure・失敗の扱いは型を渡す表示と同じで、
    /// 開始 → 処理の実行 → 終了の対と戻り値の扱いはインスタンスを渡すスコープ形と同じである。
    /// ViewModel factory と configure が失敗した場合は処理を実行しない。
    func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement?,
        configure: (@MainActor @Sendable (ViewModel) async throws -> Void)?,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T
}

public extension KsLoading {
    /// スタイルの既定メッセージ・既定の配置で既定ローディングを表示する。
    func show() async {
        await show(message: nil, placement: nil)
    }

    /// 配置を契約の既定値に委ねて既定ローディングを表示する。
    func show(message: String?) async {
        await show(message: message, placement: nil)
    }

    /// 配置を View への添付 (なければ契約の既定値) に委ねてカスタム Loading を表示する。
    func show<ViewModel: LoadingViewModel>(_ viewModel: ViewModel) async throws {
        try await show(viewModel, placement: nil)
    }

    /// メッセージも配置も省略してスコープ形で実行する。
    func start<T: Sendable>(
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        try await start(message: nil, placement: nil, action)
    }

    /// 配置を契約の既定値に委ねてスコープ形で実行する。
    func start<T: Sendable>(
        message: String?,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        try await start(message: message, placement: nil, action)
    }

    /// 配置を View への添付に委ねてカスタム Loading のスコープ形で実行する。
    func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModel: ViewModel,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        try await start(viewModel, placement: nil, action)
    }

    /// 配置を中身への添付 (なければ契約の既定値) に委ねてインライン表示する。
    func show<ViewModel: LoadingViewModel>(
        _ viewModel: ViewModel,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView
    ) async throws {
        try await show(viewModel, placement: nil, factory: factory)
    }

    /// 配置を中身への添付 (なければ契約の既定値) に委ねて SwiftUI の中身をインライン表示する。
    func show<ViewModel: LoadingViewModel, Content: View>(
        _ viewModel: ViewModel,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content
    ) async throws {
        try await show(viewModel, placement: nil, factory: factory)
    }

    /// 配置を中身への添付に委ねてインライン表示のスコープ形で実行する。
    func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModel: ViewModel,
        factory: @escaping @MainActor @Sendable (ViewModel) throws -> UIView,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        try await start(viewModel, placement: nil, factory: factory, action)
    }

    /// 配置を中身への添付に委ねて SwiftUI の中身のインライン表示のスコープ形で実行する。
    func start<ViewModel: LoadingViewModel, Content: View, T: Sendable>(
        _ viewModel: ViewModel,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) throws -> Content,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        try await start(viewModel, placement: nil, factory: factory, action)
    }

    /// 登録済みの ViewModel factory に生成を任せ、configure なしで表示する。
    func show<ViewModel: LoadingViewModel>(_ viewModelType: ViewModel.Type) async throws {
        try await show(viewModelType, placement: nil, configure: nil)
    }

    /// 登録済みの ViewModel factory に生成を任せ、configure で状態を整えてから表示する。
    func show<ViewModel: LoadingViewModel>(
        _ viewModelType: ViewModel.Type,
        configure: @escaping @MainActor @Sendable (ViewModel) async throws -> Void
    ) async throws {
        try await show(viewModelType, placement: nil, configure: configure)
    }

    /// 登録済みの ViewModel factory に生成を任せ、配置を指定して表示する。
    func show<ViewModel: LoadingViewModel>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement?
    ) async throws {
        try await show(viewModelType, placement: placement, configure: nil)
    }

    /// 登録済みの ViewModel factory に生成を任せ、configure なしでスコープ形で実行する。
    func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModelType: ViewModel.Type,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        try await start(viewModelType, placement: nil, configure: nil, action)
    }

    /// 登録済みの ViewModel factory に生成を任せ、configure で状態を整えてからスコープ形で実行する。
    func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModelType: ViewModel.Type,
        configure: @escaping @MainActor @Sendable (ViewModel) async throws -> Void,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        try await start(viewModelType, placement: nil, configure: configure, action)
    }

    /// 登録済みの ViewModel factory に生成を任せ、配置を指定してスコープ形で実行する。
    func start<ViewModel: LoadingViewModel, T: Sendable>(
        _ viewModelType: ViewModel.Type,
        placement: DialogPlacement?,
        _ action: @Sendable (@Sendable @escaping (Double) -> Void) async throws -> T
    ) async throws -> T {
        try await start(viewModelType, placement: placement, configure: nil, action)
    }
}
#endif
