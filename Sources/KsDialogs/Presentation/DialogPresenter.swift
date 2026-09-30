#if canImport(UIKit)
import UIKit

/// show 1回分の提示処理。型消去された結果でやり取りし、型の復元は呼び出し側が行う。
enum DialogPresenter {
    /// 呼び出しの時点で、提示先を待つ列の順番札を同期で取る。任意のスレッドから呼べる。
    ///
    /// show の呼び出し口が UI スレッドへ処理を移す (Task を作る) 場合に、移る前にこれを呼び、
    /// 取った札を `present` の `reservation` に渡す。移った先の処理が始まる順に関係なく、
    /// 札を取った順に列へ並ぶ。提示先があって列が空なら、札があっても今までどおり待たずに提示する (ios/ADR-0001)。
    nonisolated static func reserveTurn(
        on presentationSurface: any DialogPresentationSurface
    ) -> DialogHostWaitReservation {
        presentationSurface.hostWaitQueue.reserve()
    }

    /// ViewModel の型で factory を解決し、生成した中身をダイアログとして提示して結果を待つ。
    /// 未登録は提示先の有無にかかわらず待たずに throw し、中身の生成・表示も行わない。
    /// 提示先が無ければ失敗せず、提示先の出現を待ってから中身を作る (core/ADR-0041)。
    /// `placement` は show の引数で渡された配置で、nil なら中身への添付が使われる。
    /// `reservation` は `reserveTurn(on:)` で取った順番札で、nil なら列に着いた時点の順で並ぶ。
    @MainActor
    static func present(
        viewModel: Any,
        registry: DialogViewRegistry,
        presentationSurface: any DialogPresentationSurface,
        placement: DialogPlacement? = nil,
        reservation: DialogHostWaitReservation? = nil
    ) async throws -> DialogOutcome {
        // 列に着かずに失敗しても、札を手放して後ろの show を止めない。
        defer { reservation?.release() }
        let viewModelType = type(of: viewModel)
        guard let factory = registry.factory(forKey: DialogViewModelKey(viewModelType)) else {
            throw DialogError.viewFactoryNotRegistered(viewModelType: String(describing: viewModelType))
        }
        return try await present(
            viewModel: viewModel,
            factory: factory,
            presentationSurface: presentationSurface,
            placement: placement,
            reservation: reservation
        )
    }

    /// その場で渡された factory で中身を生成して提示する (core/ADR-0013)。
    /// レジストリは読みも書きもしないため、同じ ViewModel 型の登録・並行表示に一切干渉しない。
    ///
    /// 提示先が無ければ、結果報告口を紐付けたうえで提示先の出現を待つ (core/ADR-0041)。
    /// 待ちは、提示先が現れて列の先頭に来たとき・呼び出し元が打ち切ったとき・待っている間に
    /// 結果が確定したときのどれかで明ける。打ち切りと確定では中身を作らずに終える。
    /// 中身を作ったあとに提示面が器を載せられなかったときは、器の消失と同じくキャンセルで終える。
    /// `reservation` を渡すと、列ではその札の順番で並ぶ。
    @MainActor
    static func present(
        viewModel: Any,
        factory: DialogViewFactory,
        presentationSurface: any DialogPresentationSurface,
        placement: DialogPlacement? = nil,
        reservation: DialogHostWaitReservation? = nil
    ) async throws -> DialogOutcome {
        // 列に着かずに失敗しても (同じ ViewModel が表示中など)、札を手放して後ろの show を止めない。
        // 列に着いたあとの手放しは何もしない。
        defer { reservation?.release() }
        let viewModelType = type(of: viewModel)
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

        // 待ちは紐付けの後に置く。待っている間も同じインスタンスの再 show は「表示中」として失敗し、
        // 表示の前に VM が報告した結果もこの show の結果として受け取れる。
        let turn = await presentationSurface.hostWaitQueue.waitForTurn(
            surface: presentationSurface,
            resultChannel: resultChannel,
            reservation: reservation
        )
        guard case .ready(let slot) = turn else {
            // 表示しないまま結果が確定した。呼び出し元の打ち切りはキャンセルとして観察される。
            return Task.isCancelled ? .cancelled : (resultChannel.settledOutcome ?? .cancelled)
        }
        // 提示に進まずに終わる経路 (中身の生成失敗など) でも、列の次の 1 枚を止めない。
        defer { slot?.finish() }

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
                presentationSurface.present(container) { didPresent in
                    // 提示が終わってから、列で待っている次の 1 枚を明ける。
                    slot?.finish()
                    if !didPresent {
                        // 器を画面へ載せられなかった。器の消失と同じくキャンセルとして確定させ、
                        // 撤去済みとして配送へ進める。
                        container.handleHostLost()
                    }
                }
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
