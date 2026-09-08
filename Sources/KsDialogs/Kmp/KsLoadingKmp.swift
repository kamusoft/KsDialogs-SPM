#if canImport(UIKit)
import SwiftUI
import UIKit

/// KMP 共有コードの ViewModel を扱う、カスタム Loading の型付き登録・表示の入口 (kmp/ADR-0003・0004)。
///
/// 共有コードの ViewModel は iOS Native の ViewModel 契約に準拠しないため、Native の登録面
/// (`Loading.shared.registry`) では受けられない。この面が型付きのまま受けて同じレジストリへ載せるので、
/// 共有コードからの表示も同じ紐付けを引く。
/// 中身は従来 View 系 (`UIView`) と SwiftUI のどちらでも書け、どちらでも観察できる挙動は同じである。
///
///     Loading.shared.kmp.register(SharedUploadViewModel.self) { viewModel in
///         UploadIndicator(viewModel: viewModel)
///     }
///     try await Loading.shared.kmp.show(SharedUploadViewModel())
///
/// 見た目のスタイルと既定ローディングの器メタ属性は Native の入口 (`Loading.shared.style` /
/// `Loading.shared.options`) で設定する。
public final class KsLoadingKmp: Sendable {
    private let coordinator: LoadingCoordinator

    /// 既定の状態の正とレジストリを使う入口を作る。
    /// `Loading` から取り出す入口 (`Loading.shared.kmp`) と同じ状態を共有する (core/ADR-0002・0024)。
    public convenience init() {
        self.init(coordinator: .shared)
    }

    init(coordinator: LoadingCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: 登録

    /// 共有 VM の型に対するカスタム Loading の View factory を登録する。
    /// 同じ型への再登録は後勝ちで置き換え、factory は表示のたびに呼ばれる (core/ADR-0005)。
    public func register<ViewModel: AnyObject>(
        _ viewModelClass: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> UIView
    ) {
        coordinator.registry.register(
            LoadingViewFactory.kmp(viewModelClass, factory: factory),
            forKey: DialogViewModelKey(viewModelClass)
        )
    }

    /// 共有 VM の型に対する SwiftUI の中身の factory を登録する。
    /// 従来 View 系の登録と同名で、factory の戻り値の型だけが違う。
    ///
    /// 器の属性は中身への添付 (`ksDialogOptions` / `ksDialogPlacement`) で供給する。
    public func register<ViewModel: AnyObject, Content: View>(
        _ viewModelClass: ViewModel.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) -> Content
    ) {
        coordinator.registry.register(
            LoadingViewFactory.kmp(viewModelClass, factory: factory),
            forKey: DialogViewModelKey(viewModelClass)
        )
    }

    // MARK: 表示

    /// 共有 VM を渡して登録済みのカスタム Loading を表示し、合流1件を開始する。
    ///
    /// 対応する終了は `Loading.shared.hide()` だけである。処理の走行に合わせて開始と終了を対にしたい
    /// 場合は、共有コードのスコープ形から呼ぶ (進捗の報告口もそちらにある)。
    ///
    /// 未登録の共有 VM の型は構成ミスとして `DialogError` を投げ、表示は行われない。
    ///
    /// - Parameter placement: 配置。nil なら中身への添付、添付もなければ契約の既定値 (core/ADR-0015)
    @MainActor
    public func show<ViewModel: AnyObject>(
        _ viewModel: ViewModel,
        placement: DialogPlacement? = nil
    ) async throws {
        // Swift から渡された共有 VM には進捗の転送先が無い (受け口は共有コード側の面のため)
        let request = try LoadingContentRequest.kmp(
            viewModel: viewModel,
            progress: nil,
            registry: coordinator.registry
        )
        _ = try await coordinator.beginUse(request, message: nil, placement: placement)
    }
}

extension LoadingViewFactory {
    /// 共有コードの ViewModel 向けの、従来 View 系 factory を型消去する。
    ///
    /// 出来上がる内部表現は Native の登録経路と同じ1本で、提示・進捗転送・レイアウトの経路は
    /// 共有される (core/ADR-0011)。
    static func kmp<ViewModel: AnyObject>(
        _ viewModelClass: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> UIView
    ) -> LoadingViewFactory {
        LoadingViewFactory { viewModel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return DialogContent(view: factory(typedViewModel))
        }
    }

    /// 共有コードの ViewModel 向けの、SwiftUI factory を型消去する。
    /// ホスティングはこの変換の中で完結し、従来 View 系と同じ内部表現になる。
    static func kmp<ViewModel: AnyObject, Content: View>(
        _ viewModelClass: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> Content
    ) -> LoadingViewFactory {
        LoadingViewFactory { viewModel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return DialogSwiftUIHost.makeContent(factory(typedViewModel))
        }
    }
}
#endif
