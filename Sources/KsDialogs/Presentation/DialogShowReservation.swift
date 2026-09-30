#if canImport(UIKit)
/// `Dialog.reserveShow()` で取った、表示の順番の予約。
///
/// 表示を待つ列の順番札を包む。予約は 1 回の show にだけ使え、使わずに捨てた予約は解放された時点で
/// 手放される。
///
/// 別モジュールのブリッジ (MAUI の iOS 互換面) が、UI スレッドへ移る前に順番を取るための口で、
/// 利用者向けの公開面には出さない。
@_spi(KsDialogsBridge)
public final class DialogShowReservation: Sendable {
    /// 包んでいる順番札。
    let turn: DialogHostWaitReservation

    init(_ turn: DialogHostWaitReservation) {
        self.turn = turn
    }
}
#endif
