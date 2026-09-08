#if canImport(UIKit)
import UIKit

/// show 1回分の提示処理。型消去された結果でやり取りし、型の復元は呼び出し側が行う。
enum DialogPresenter {
    /// ViewModel の型で factory を解決し、生成した中身をダイアログとして提示して結果を待つ。
    /// 未登録・提示先不在は結果を返さずに throw し、中身の生成・表示も行わない。
    /// `placement` は show の引数で渡された配置で、nil なら中身への添付が使われる。
    @MainActor
    static func present(
        viewModel: Any,
        registry: DialogViewRegistry,
        presentationSurface: any DialogPresentationSurface,
        placement: DialogPlacement? = nil
    ) async throws -> DialogOutcome {
        let viewModelType = type(of: viewModel)
        guard let factory = registry.factory(forKey: DialogViewModelKey(viewModelType)) else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        return try await present(
            viewModel: viewModel,
            factory: factory,
            presentationSurface: presentationSurface,
            placement: placement
        )
    }

    /// その場で渡された factory で中身を生成して提示する (core/ADR-0013)。
    /// レジストリは読みも書きもしないため、同じ ViewModel 型の登録・並行表示に一切干渉しない。
    @MainActor
    static func present(
        viewModel: Any,
        factory: DialogViewFactory,
        presentationSurface: any DialogPresentationSurface,
        placement: DialogPlacement? = nil
    ) async throws -> DialogOutcome {
        let viewModelType = type(of: viewModel)
        guard presentationSurface.canPresent else {
            throw DialogError.presentationHostUnavailable
        }

        let resultChannel = DialogResultChannel()

        // 結果報告口の紐付けは中身の生成より前に済ませ、factory 本体からも `vm.notifier` が読めるようにする
        // (core/ADR-0018)。同じインスタンスが既に表示中なら、結果に化けさせずに構成ミスとして失敗する。
        // この show が使う factory の宣言結果型も一緒に控え、表示中の報告口の型検証をこの1回の
        // show に固定する (表示中の登録し直しに引きずられないようにするため)。
        let boundViewModel = viewModel as AnyObject
        guard DialogNotifierBindings.shared.bind(
            boundViewModel,
            to: resultChannel,
            declaredResultType: factory.declaredResultType
        ) else {
            throw DialogError.viewModelAlreadyShowing(viewModelType: String(describing: viewModelType))
        }
        // 紐付け後に show が終わる全経路 (正常配送・中身の生成失敗・呼び出し元キャンセル・器消失) で外す。
        // 呼び出し元へ結果や例外が渡るのはこの除去のあとになる。
        defer { DialogNotifierBindings.shared.unbind(boundViewModel, resultChannel: resultChannel) }

        guard let content = try factory.makeContent(viewModel, resultChannel) else {
            throw DialogError.viewFactoryTypeMismatch(viewModelType: String(describing: viewModelType))
        }
        let container = DialogContainerViewController(
            content: content,
            resultChannel: resultChannel,
            placement: placement
        )
        // 閉鎖信号と取り消しを器が受け取れるようにしてから画面へ載せる。
        container.observeResultChannel()
        container.onDismissRequest = { [weak container] removalCompletion in
            guard let container else {
                // 器が解放済みなら撤去も済んでいる。
                removalCompletion()
                return
            }
            presentationSurface.dismiss(container, completion: removalCompletion)
        }
        // 初期状態を反映した内容のサイズを確定させてから提示する。
        container.prepareForPresentation(inBounds: presentationSurface.presentationBounds)

        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<DialogOutcome, Never>) in
                // 配送は退出の演出・覆いの消滅・器の撤去がすべて済んだあとに届く (core/ADR-0017)。
                // 配送口は器とは別の寿命を持つので、撤去の完了を待つ間に器が解放されても待ち続けない。
                container.outcomeDelivery.setDestination { outcome in
                    continuation.resume(returning: outcome)
                }
                presentationSurface.present(container)
            }
        } onCancel: {
            // 呼び出し元が待つのをやめたらダイアログを残さない。
            // 未確定ならキャンセルとして確定し、退出中なら演出を待たずに撤去へ進む。
            resultChannel.cancelFromCaller()
        }
        // 呼び出し元の取り消しは、確定済みの結果より優先してキャンセルとして観察される。
        return Task.isCancelled ? .cancelled : outcome
    }
}
#endif
