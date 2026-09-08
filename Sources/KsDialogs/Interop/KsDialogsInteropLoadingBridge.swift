#if canImport(UIKit)
import Foundation
import UIKit

/// 合流1件の開始の通知。開始できたときだけハンドルが入り、失敗したときだけ理由が入る。
public typealias KsDialogsInteropLoadingBeginCompletion =
    (KsDialogsInteropLoadingUseHandle?, NSError?) -> Void

/// KMP からの Loading 委譲呼び出しを受ける ObjC 互換面 (kmp/ADR-0002)。
///
/// 合流カウント・表示世代・最新のメッセージと進捗はすべて Native ライブラリの状態の正が持ち、
/// この面は共有コードの呼び出しをそこへ渡すだけである (core/ADR-0024)。
/// 見た目のスタイルと既定ローディングの器メタ属性はこの面を渡らない — 色が共有コードの境界を
/// 渡らないため、それらは Swift の入口 (`Loading`) の設定プロパティだけで扱う。
///
/// 共有コードは合流1件の開始と終了を別々の呼び出しで行うため、開始で返すハンドルがその1件の
/// 終了と進捗報告の宛先になる。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない。
/// 利用者向けの入口は型付きの `Loading` (iOS Native) と `KsLoadingKmp` (KMP 共有コードの ViewModel 向け) で、
/// 登録・表示はそちらだけで完結する (kmp/ADR-0003・0004)。
@objc(KSDInteropLoadingBridge)
public final class KsDialogsInteropLoadingBridge: NSObject, Sendable {
    /// 既定の状態の正とレジストリを使う共有インスタンス。
    @objc(sharedBridge)
    public static let shared = KsDialogsInteropLoadingBridge()

    private let coordinator: LoadingCoordinator

    /// 進捗報告と終了を呼ばれた順に受理させる待ち行列。
    /// 独立した Task で個別に投げると、報告した直後の終了が報告を追い越して
    /// 最終報告が旧世代として捨てられるため、この2つは同じ鎖に載せる。
    private let reportQueue = LoadingReportQueue()

    public override convenience init() {
        self.init(coordinator: .shared)
    }

    init(coordinator: LoadingCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    /// ViewModel のクラスをキーにカスタム Loading の View factory を登録する。
    /// factory は表示のたびに呼ばれ、View を毎回新規に生成する (core/ADR-0005)。
    ///
    /// Swift の型付き入口 (`KsLoadingKmp`) と同じレジストリに載るため、
    /// どちらの入口で登録しても同じ紐付けが引ける。
    @objc(registerViewFactoryForViewModelClass:factory:)
    public func registerViewFactory(
        forViewModelClass viewModelClass: AnyClass,
        factory: @escaping @MainActor (Any) -> UIView
    ) {
        let boxedFactory = UncheckedSendableBox(factory)
        let erasedFactory = LoadingViewFactory { viewModel in
            DialogContent(view: boxedFactory.value(viewModel))
        }
        coordinator.registry.register(erasedFactory, forKey: DialogViewModelKey(viewModelClass))
    }

    /// 既定ローディングで合流1件を開始する。
    ///
    /// 通知が届くのは操作ブロックが有効になった時点で、入りの演出の完了は待たない。
    /// 対応する終了を行わない表示 (共有コードの show) では、返るハンドルを捨ててよい。
    @objc(beginBuiltinWithMessage:placement:completion:)
    public func beginBuiltin(
        message: String?,
        placement: KsDialogsInteropPlacement?,
        completion: @escaping KsDialogsInteropLoadingBeginCompletion
    ) {
        let resolvedPlacement = placement.map { DialogPlacement($0) }
        begin(completion) { coordinator in
            try await coordinator.beginUse(.builtin, message: message, placement: resolvedPlacement)
        }
    }

    /// 登録済みのカスタム Loading View で合流1件を開始する。
    ///
    /// 未登録の ViewModel 型は構成ミスとして失敗の通知になり、表示は行われない。
    ///
    /// - Parameter progress: 進捗の転送先。共有 VM が受け口を持たないときは nil を渡す。
    @objc(beginViewModel:placement:progress:completion:)
    public func begin(
        viewModel: Any,
        placement: KsDialogsInteropPlacement?,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping KsDialogsInteropLoadingBeginCompletion
    ) {
        let resolvedPlacement = placement.map { DialogPlacement($0) }
        let boxedViewModel = UncheckedSendableBox(viewModel)
        begin(completion) { coordinator in
            let request = try LoadingContentRequest.kmp(
                viewModel: boxedViewModel.value,
                progress: progress,
                registry: coordinator.registry
            )
            return try await coordinator.beginUse(request, message: nil, placement: resolvedPlacement)
        }
    }

    /// 合流1件を終了する。合流最後の1件なら器の撤去が完了してから通知が届く。
    /// 旧世代のハンドルでの終了は現在の表示に影響しない。
    @objc(endUse:completion:)
    public func endUse(
        _ handle: KsDialogsInteropLoadingUseHandle,
        completion: @escaping () -> Void
    ) {
        let boxedCompletion = UncheckedSendableBox(completion)
        reportQueue.enqueue { [coordinator] in
            await coordinator.endUse(handle.token)
            boxedCompletion.value()
        }
    }

    /// 進捗を報告する。任意のスレッドから呼べ、受理は UI スレッド上で呼ばれた順に直列化される。
    /// 旧世代のハンドルでの報告は捨てられる。
    @objc(reportProgress:handle:)
    public func report(progress: Double, handle: KsDialogsInteropLoadingUseHandle) {
        reportQueue.enqueue { [coordinator] in
            coordinator.report(progress: progress, token: handle.token)
        }
    }

    /// 合流数によらず表示を閉じる。出の演出と器の撤去が完了してから通知が届く。
    @objc(hideWithCompletion:)
    public func hide(completion: @escaping () -> Void) {
        let boxedCompletion = UncheckedSendableBox(completion)
        Task { @MainActor in
            await coordinator.hide()
            boxedCompletion.value()
        }
    }

    /// 表示中のメッセージを更新する。合流には関与しない。
    @objc(setLoadingMessage:completion:)
    public func setMessage(_ message: String?, completion: @escaping () -> Void) {
        let boxedCompletion = UncheckedSendableBox(completion)
        Task { @MainActor in
            coordinator.setMessage(message)
            boxedCompletion.value()
        }
    }

    /// 開始の操作を UI スレッドで行い、結末をちょうど1回だけ通知する。
    ///
    /// 通知が1つも届かないと共有コードの待機が解けないため、想定していない失敗も通知へ変換する。
    private func begin(
        _ completion: @escaping KsDialogsInteropLoadingBeginCompletion,
        _ operation: @escaping @MainActor (LoadingCoordinator) async throws -> LoadingUseToken
    ) {
        let boxedCompletion = UncheckedSendableBox(completion)
        Task { @MainActor in
            do {
                let token = try await operation(coordinator)
                boxedCompletion.value(KsDialogsInteropLoadingUseHandle(token: token), nil)
            } catch {
                boxedCompletion.value(nil, error as NSError)
            }
        }
    }
}
#endif
