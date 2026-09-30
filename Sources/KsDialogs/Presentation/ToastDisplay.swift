#if canImport(UIKit)
import Foundation
import UIKit

/// 表示中の Toast 1枚分の状態 (core/ADR-0030 の「1 Toast 1器」)。
///
/// 中身は取り付けの時点で作るので、取り付け先を待つ間は中身の指定だけを持つ。
/// 取り付けた後は、器・ViewModel・演出フックへの参照を、撤去の完了までここが握る。
/// 消滅の期限は単調時計の時刻で持ち、一度決めたら動かさないので、器を作り直しても巻き戻らない。
///
/// 期限は、表示の開始処理の時点でアプリが前面にいるのに取り付け先が無ければ未確定 (nil) のまま待ち、
/// 取り付けた時点か、取り付ける前にアプリが前面を離れた時点から数えて決める (core/ADR-0043)。
/// それ以外は受理の時点から数えて、開始処理で決める。
@MainActor
final class ToastDisplay {
    /// 中身の指定。取り付けの時点でここから中身を作る。
    let request: ToastContentRequest

    /// 受理時点で読んだスタイル。表示中の設定変更には追随しない。
    let style: ToastStyle

    /// カスタム Toast View の ViewModel。取り付け前とデフォルト View では nil。
    var viewModel: AnyObject?

    /// 表示 API の引数で渡された配置。
    let showPlacement: DialogPlacement?

    /// show 引数も添付も無いときに採る配置 (style のアプリ既定配置 か 契約既定値)。
    let fallbackPlacement: DialogPlacement

    /// 受理の時刻。
    let acceptedAt: ContinuousClock.Instant

    /// 表示時間。
    let duration: Duration

    /// 消滅の期限。数え始める時点がまだ来ていない間は nil。
    private(set) var deadline: ContinuousClock.Instant?

    /// 取り付け済みの器。取り付け先がまだ無い間は nil。
    var container: ToastContainerViewController?

    /// 期限を待つ仕事。
    var timerTask: Task<Void, Never>?

    /// 撤去へ進んだか。期限の到達と後始末が重なっても1回しか進まないための印。
    var isFinishing = false

    init(
        request: ToastContentRequest,
        style: ToastStyle,
        showPlacement: DialogPlacement?,
        fallbackPlacement: DialogPlacement,
        acceptedAt: ContinuousClock.Instant,
        duration: Duration
    ) {
        self.request = request
        self.style = style
        self.showPlacement = showPlacement
        self.fallbackPlacement = fallbackPlacement
        self.acceptedAt = acceptedAt
        self.duration = duration
    }

    /// `start` から表示時間を数えて期限を決める。決めたときだけ true を返す。
    ///
    /// 既に決まっている期限は動かさない。載せ直しや前面・背面の行き来で残り時間を巻き戻さないため。
    @discardableResult
    func fixDeadline(startingAt start: ContinuousClock.Instant) -> Bool {
        guard deadline == nil else { return false }
        deadline = start.advanced(by: duration)
        return true
    }

    /// 期限に達したか。期限の決まっていない表示は達していない。
    func hasReachedDeadline(at now: ContinuousClock.Instant = .now) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// 撤去の完了後に、保持していた参照を手放す。
    func releaseResources() {
        container = nil
        timerTask = nil
        viewModel = nil
    }
}
#endif
