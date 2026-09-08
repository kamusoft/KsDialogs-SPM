#if canImport(UIKit)
import Foundation
import UIKit

/// KMP からの Toast 委譲呼び出しを受ける ObjC 互換面 (kmp/ADR-0002)。
///
/// レジストリ・一括設定・表示中のリストと各表示の期限はすべて Native ライブラリの状態の正が持ち、
/// この面は共有コードの呼び出しをそこへ渡すだけである。見た目のスタイルとアプリ既定配置は
/// この面を渡らない — 色が共有コードの境界を渡らないため、それらは Swift の入口 (`Toast`) の
/// 設定プロパティだけで扱う。
///
/// Toast は fire-and-forget なので、この面の表示も完了通知を持たない (core/ADR-0031)。
/// 呼び出し元へ返るのは解決の失敗 (未登録の ViewModel 型) だけで、受理より後の失敗は
/// その表示 1 枚の破棄に留まる。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない。
/// 利用者向けの入口は型付きの `Toast` (iOS Native) と `KsToastKmp` (KMP 共有コードの ViewModel 向け) で、
/// 登録・表示はそちらだけで完結する (kmp/ADR-0003・0004)。
@objc(KSDInteropToastBridge)
public final class KsDialogsInteropToastBridge: NSObject, Sendable {
    /// 既定の状態の正とレジストリを使う共有インスタンス。
    @objc(sharedBridge)
    public static let shared = KsDialogsInteropToastBridge()

    private let coordinator: ToastCoordinator

    public override convenience init() {
        self.init(coordinator: .shared)
    }

    init(coordinator: ToastCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    /// ViewModel のクラスをキーにカスタム Toast の View factory を登録する。
    /// factory は表示のたびに呼ばれ、View を毎回新規に生成する (core/ADR-0005)。
    ///
    /// Swift の型付き入口 (`KsToastKmp`) と同じレジストリに載るため、
    /// どちらの入口で登録しても同じ紐付けが引ける。
    @objc(registerViewFactoryForViewModelClass:factory:)
    public func registerViewFactory(
        forViewModelClass viewModelClass: AnyClass,
        factory: @escaping @MainActor (Any) -> UIView
    ) {
        let boxedFactory = UncheckedSendableBox(factory)
        let erasedFactory = ToastViewFactory { viewModel in
            DialogContent(view: boxedFactory.value(viewModel))
        }
        coordinator.registry.register(erasedFactory, forKey: DialogViewModelKey(viewModelClass))
    }

    /// デフォルト View でメッセージを表示する。呼び出しは即座に戻る。
    ///
    /// - Parameter duration: 表示するミリ秒。nil なら `ToastStyle` の既定 duration
    @objc(showMessage:duration:placement:)
    public func show(
        message: String,
        duration: NSNumber?,
        placement: KsDialogsInteropPlacement?
    ) {
        // デフォルト View には中身の解決の失敗が無いため、この経路は失敗しない。
        try? coordinator.accept(
            .builtin(message: message),
            duration: duration?.intValue,
            placement: placement.map { DialogPlacement($0) }
        )
    }

    /// 登録済みのカスタム Toast View を表示する。呼び出しは即座に戻る。
    ///
    /// 未登録の ViewModel 型は構成ミスとして受理そのものが失敗し、表示は行われない。
    ///
    /// - Returns: 受理できなければその理由。受理できたら nil。
    @objc(showViewModel:duration:placement:)
    public func show(
        viewModel: Any,
        duration: NSNumber?,
        placement: KsDialogsInteropPlacement?
    ) -> NSError? {
        do {
            let request = try ToastContentRequest.kmp(
                viewModel: viewModel,
                registry: coordinator.registry
            )
            try coordinator.accept(
                request,
                duration: duration?.intValue,
                placement: placement.map { DialogPlacement($0) }
            )
            return nil
        } catch {
            return error as NSError
        }
    }
}
#endif
