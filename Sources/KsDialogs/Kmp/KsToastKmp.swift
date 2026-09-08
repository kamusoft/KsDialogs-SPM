#if canImport(UIKit)
import SwiftUI
import UIKit

/// KMP 共有コードの ViewModel を扱う、カスタム Toast の型付き登録・表示の入口 (kmp/ADR-0003・0004)。
///
/// 共有コードの ViewModel は iOS Native の ViewModel 契約に準拠しないため、Native の登録面
/// (`Toast.shared.registry`) では受けられない。この面が型付きのまま受けて同じレジストリへ載せるので、
/// 共有コードからの表示も同じ紐付けを引く。
/// 中身は従来 View 系 (`UIView`) と SwiftUI のどちらでも書け、どちらでも観察できる挙動は同じである。
///
///     Toast.shared.kmp.register(SharedNoticeViewModel.self) { viewModel in
///         NoticeBanner(message: viewModel.message)
///     }
///     try Toast.shared.kmp.show(SharedNoticeViewModel(message: "保存しました"))
///
/// 見た目のスタイルとアプリ既定配置は Native の入口 (`Toast.shared.style`) で設定する。
public final class KsToastKmp: Sendable {
    private let coordinator: ToastCoordinator

    /// 既定の状態の正とレジストリを使う入口を作る。
    /// `Toast` から取り出す入口 (`Toast.shared.kmp`) と同じ状態を共有する (core/ADR-0002)。
    public convenience init() {
        self.init(coordinator: .shared)
    }

    init(coordinator: ToastCoordinator) {
        self.coordinator = coordinator
    }

    // MARK: 登録

    /// 共有 VM の型に対するカスタム Toast の View factory を登録する。
    /// 同じ型への再登録は後勝ちで置き換え、factory は表示のたびに呼ばれる (core/ADR-0005)。
    public func register<ViewModel: AnyObject>(
        _ viewModelClass: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> UIView
    ) {
        coordinator.registry.register(
            ToastViewFactory.kmp(viewModelClass, factory: factory),
            forKey: DialogViewModelKey(viewModelClass)
        )
    }

    /// 共有 VM の型に対する SwiftUI の中身の factory を登録する。
    /// 従来 View 系の登録と同名で、factory の戻り値の型だけが違う。
    ///
    /// 器の属性は中身への添付 (`ksDialogPlacement` / `ksDialogTransition`) で供給する。
    public func register<ViewModel: AnyObject, Content: View>(
        _ viewModelClass: ViewModel.Type,
        @ViewBuilder factory: @escaping @MainActor @Sendable (ViewModel) -> Content
    ) {
        coordinator.registry.register(
            ToastViewFactory.kmp(viewModelClass, factory: factory),
            forKey: DialogViewModelKey(viewModelClass)
        )
    }

    // MARK: 表示

    /// 共有 VM を渡して登録済みのカスタム Toast を表示する。
    ///
    /// fire-and-forget なので戻り値は無く、表示の終了を待つ手段も無い (core/ADR-0031)。
    /// 未登録の共有 VM の型は構成ミスとして `DialogError` を投げ、表示は行われない。
    ///
    /// - Parameters:
    ///   - duration: 表示するミリ秒。nil なら `ToastStyle` の既定 duration
    ///   - placement: 配置。nil なら中身への添付、添付もなければスタイル・契約の既定値 (core/ADR-0015)
    public func show<ViewModel: AnyObject>(
        _ viewModel: ViewModel,
        duration: Int? = nil,
        placement: DialogPlacement? = nil
    ) throws {
        let request = try ToastContentRequest.kmp(
            viewModel: viewModel,
            registry: coordinator.registry
        )
        try coordinator.accept(request, duration: duration, placement: placement)
    }
}

extension ToastViewFactory {
    /// 共有コードの ViewModel 向けの、従来 View 系 factory を型消去する。
    ///
    /// 出来上がる内部表現は Native の登録経路と同じ1本で、提示・レイアウト・演出の経路は
    /// 共有される (core/ADR-0011)。
    static func kmp<ViewModel: AnyObject>(
        _ viewModelClass: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> UIView
    ) -> ToastViewFactory {
        ToastViewFactory { viewModel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return DialogContent(view: factory(typedViewModel))
        }
    }

    /// 共有コードの ViewModel 向けの、SwiftUI factory を型消去する。
    /// ホスティングはこの変換の中で完結し、従来 View 系と同じ内部表現になる。
    static func kmp<ViewModel: AnyObject, Content: View>(
        _ viewModelClass: ViewModel.Type,
        factory: @escaping @MainActor @Sendable (ViewModel) -> Content
    ) -> ToastViewFactory {
        ToastViewFactory { viewModel in
            guard let typedViewModel = viewModel as? ViewModel else { return nil }
            return DialogSwiftUIHost.makeContent(factory(typedViewModel))
        }
    }
}
#endif
