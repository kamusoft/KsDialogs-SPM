#if canImport(UIKit)
import SwiftUI
import UIKit

/// KMP 共有コードの ViewModel を扱う、型付きの登録・表示の入口 (kmp/ADR-0003・0004)。
///
/// 共有コードの ViewModel は iOS Native の ViewModel 契約に準拠しないため、結果型は ViewModel からは
/// 導出できない。この面では結果型を `result:` 引数で受け取り、省略した場合は真偽値になる (core/ADR-0012)。
/// 中身は従来 View 系 (`UIView`) と SwiftUI のどちらでも書け、どちらでも観察できる挙動は同じである。
///
/// 登録は Native ライブラリと同じレジストリに載るため、共有コードからの show も同じ紐付けを引く。
///
///     Dialog.shared.kmp.register(SharedConfirmViewModel.self) { viewModel, notifier in
///         ConfirmContent(message: viewModel.message, notifier: notifier)
///     }
///     let result = try await Dialog.shared.kmp.show(SharedConfirmViewModel(message: "削除しますか?"))
public final class KsDialogsKmp: Sendable {
    private let registry: DialogViewRegistry
    private let bridge: KsDialogsInteropBridge

    /// 既定のレジストリと提示先解決を使う入口を作る。
    /// `Dialog` から取り出す入口 (`Dialog.shared.kmp`) と同じレジストリを共有する (core/ADR-0002・0004)。
    public convenience init() {
        self.init(presentationSurface: UIKitDialogPresentationSurface())
    }

    init(registry: DialogViewRegistry = .shared, presentationSurface: any DialogPresentationSurface) {
        self.registry = registry
        bridge = KsDialogsInteropBridge(registry: registry, presentationSurface: presentationSurface)
    }

    // MARK: 登録

    /// 共有 VM の型に対する View factory を登録する。結果型は真偽値になる。
    /// 同じ型への再登録は後勝ちで置き換え、factory は show のたびに呼ばれる (core/ADR-0005)。
    public func register<ViewModel: AnyObject>(
        _ viewModelClass: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<Bool>) -> UIView
    ) {
        register(viewModelClass, result: Bool.self, factory: factory)
    }

    /// 共有 VM の型に対する View factory を、結果型つきで登録する。
    ///
    /// `result:` に渡した型がそのまま結果報告口の型になり、show の戻り値の型にもなる。
    /// 共有コードの ViewModel が宣言している結果型と同じものを渡すこと —
    /// 食い違いは show の結果を復元する時点で型付きの失敗として現れる (kmp/ADR-0004)。
    public func register<ViewModel: AnyObject, Result: Sendable>(
        _ viewModelClass: ViewModel.Type,
        result: Result.Type,
        factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<Result>) -> UIView
    ) {
        registry.register(
            DialogViewFactory.make(viewModelClass, result: result, factory: factory),
            forKey: DialogViewModelKey(viewModelClass)
        )
    }

    /// 共有 VM の型に対する SwiftUI の中身の factory を登録する。結果型は真偽値になる。
    /// 従来 View 系の登録と同名で、factory の戻り値の型だけが違う。
    ///
    /// 器の属性は中身への添付 (`ksDialogOptions` / `ksDialogPlacement`) で供給する。
    /// 添付の扱いは iOS Native の直接登録と同じ供給契約に従う (core/ADR-0015)。
    public func register<ViewModel: AnyObject, Content: View>(
        _ viewModelClass: ViewModel.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<Bool>) -> Content
    ) {
        register(viewModelClass, result: Bool.self, factory: factory)
    }

    /// 共有 VM の型に対する SwiftUI の中身の factory を、結果型つきで登録する。
    public func register<ViewModel: AnyObject, Result: Sendable, Content: View>(
        _ viewModelClass: ViewModel.Type,
        result: Result.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel, DialogNotifier<Result>) -> Content
    ) {
        registry.register(
            DialogViewFactory.make(viewModelClass, result: result, factory: factory),
            forKey: DialogViewModelKey(viewModelClass)
        )
    }

    /// 共有 VM の型に対する、ViewModel だけを受け取る View factory を登録する。結果型は真偽値になる。
    /// 結果報告口は中身の中から `notifier(for:)` で取り出す (core/ADR-0018)。
    public func register<ViewModel: AnyObject>(
        _ viewModelClass: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> UIView
    ) {
        register(viewModelClass, result: Bool.self, factory: factory)
    }

    /// 共有 VM の型に対する、ViewModel だけを受け取る View factory を、結果型つきで登録する。
    ///
    /// ここで渡した結果型が結果報告口の型になり、`notifier(for:result:)` で指定する型にもなる。
    public func register<ViewModel: AnyObject, Result: Sendable>(
        _ viewModelClass: ViewModel.Type,
        result: Result.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> UIView
    ) {
        registry.register(
            DialogViewFactory.make(viewModelClass, result: result, factory: factory),
            forKey: DialogViewModelKey(viewModelClass)
        )
    }

    /// 共有 VM の型に対する、ViewModel だけを受け取る SwiftUI の中身の factory を登録する。
    /// 結果型は真偽値になる。
    public func register<ViewModel: AnyObject, Content: View>(
        _ viewModelClass: ViewModel.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) -> Content
    ) {
        register(viewModelClass, result: Bool.self, factory: factory)
    }

    /// 共有 VM の型に対する、ViewModel だけを受け取る SwiftUI の中身の factory を、結果型つきで登録する。
    public func register<ViewModel: AnyObject, Result: Sendable, Content: View>(
        _ viewModelClass: ViewModel.Type,
        result: Result.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) -> Content
    ) {
        registry.register(
            DialogViewFactory.make(viewModelClass, result: result, factory: factory),
            forKey: DialogViewModelKey(viewModelClass)
        )
    }

    // MARK: 結果報告口

    /// 表示中の共有 VM に紐付いた結果報告口を取り出す。結果型は真偽値になる。
    public func notifier<ViewModel: AnyObject>(
        for viewModel: ViewModel
    ) throws -> DialogNotifier<Bool>? {
        try notifier(for: viewModel, result: Bool.self)
    }

    /// 表示中の共有 VM に紐付いた結果報告口を、結果型を指定して取り出す (core/ADR-0018)。
    ///
    /// 共有 VM は iOS Native の ViewModel 契約に準拠せず結果型も宣言しないため、
    /// Native の `viewModel.notifier` の代わりにこの入口で取り出す。
    /// 紐付けと取り出しはインスタンスの同一性で行い、ViewModel の等価比較には依存しない。
    ///
    /// show が中身を生成する直前に紐付き、結果が呼び出し元へ渡る前に外れる。
    /// したがって show の前と終わったあとは nil で、表示中だけ値を返す。
    ///
    ///     Dialog.shared.kmp.register(SharedConfirmViewModel.self) { viewModel in
    ///         ConfirmContent(notifier: try? Dialog.shared.kmp.notifier(for: viewModel))
    ///     }
    ///
    /// `result:` に登録時の結果型と違う型を渡した場合は、nil ではなく型付きの失敗になる —
    /// 「表示していないから空」と「結果型を取り違えている」を取り違えないようにするため。
    /// 判定は表示中かどうかより先に行うので、show の前でも失敗として報告される。
    /// 表示中の判定に使う結果型は、その show を始めた時点の登録で固定される。
    /// 表示中に同じ VM 型を別の結果型で登録し直しても、出ているダイアログの報告口は元の型で引ける。
    public func notifier<ViewModel: AnyObject, Result: Sendable>(
        for viewModel: ViewModel,
        result: Result.Type
    ) throws -> DialogNotifier<Result>? {
        let binding = DialogNotifierBindings.shared.binding(for: viewModel)
        // 表示中は show を始めた時点の結果型で判定し、表示していないときだけ現在の登録を見る。
        let declaredResultType = if let binding {
            binding.declaredResultType
        } else {
            registry
                .factory(forKey: DialogViewModelKey(type(of: viewModel)))?
                .declaredResultType
        }
        if let declaredResultType, declaredResultType != DialogDeclaredResultType(result) {
            throw KsDialogsKmpError.resultTypeMismatch(
                expected: String(describing: result),
                actual: declaredResultType.name
            )
        }
        guard let binding else {
            return nil
        }
        return DialogNotifier(resultChannel: binding.resultChannel)
    }

    // MARK: 表示

    /// 共有 VM を渡してダイアログを表示し、真偽値の結果を待つ。
    ///
    /// `placement` を渡すと、中身に添付された placement をまるごと置換して配置を決める (core/ADR-0015)。
    /// 構成エラーと結果型の不一致では、結果を返さずに throw する — 共有 VM の紐付けと結果型に
    /// まつわる失敗は `KsDialogsKmpError`、提示できないなどそれ以外の失敗は `DialogError` になる。
    @MainActor
    public func show<ViewModel: AnyObject>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil
    ) async throws -> DialogResult<Bool> {
        try await show(viewModel, result: Bool.self, placement: placement)
    }

    /// 共有 VM を渡してダイアログを表示し、指定した型の結果を待つ。
    ///
    /// 待機を打ち切る (呼び出し元の Task をキャンセルする) と、この show のダイアログだけが閉じ、
    /// 結果は cancelled としてちょうど1回確定する。ほかに表示中のダイアログは影響を受けない。
    @MainActor
    public func show<ViewModel: AnyObject, Result: Sendable>(
        _ viewModel: ViewModel,
        result: Result.Type,
        placement: DialogPlacement? = nil
    ) async throws -> DialogResult<Result> {
        let interopResult = await present(viewModel, placement: placement)
        switch interopResult.kind {
        case .completed:
            guard let value = interopResult.value as? Result else {
                throw KsDialogsKmpError.resultTypeMismatch(
                    expected: String(describing: Result.self),
                    actual: Self.typeName(of: interopResult.value)
                )
            }
            return .completed(value)
        case .cancelled:
            return .cancelled
        case .error:
            throw KsDialogsKmpError.publicError(from: interopResult.error)
        }
    }

    /// 機械面へ委譲して結果を待つ。
    /// 待機が打ち切られたら、この show のハンドルで当該ダイアログだけを閉じる。
    @MainActor
    private func present(
        _ viewModel: Any,
        placement: DialogPlacement?
    ) async -> KsDialogsInteropResult {
        let cancellation = KmpShowCancellation()
        let boxedResult = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                cancellation.attach(
                    bridge.show(viewModel, resolvedPlacement: placement) { result in
                        continuation.resume(returning: UncheckedSendableBox(result))
                    }
                )
            }
        } onCancel: {
            cancellation.cancel()
        }
        return boxedResult.value
    }

    /// 結果値の型の名前。値がなければその旨を返す。
    private static func typeName(of value: Any?) -> String {
        guard let value else { return "nil" }
        return String(describing: type(of: value))
    }
}
#endif
