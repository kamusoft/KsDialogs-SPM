#if canImport(UIKit)
import Foundation

/// show 1回分の取り消し操作を指すハンドル。
///
/// 互換面の show は結果を completion で返すだけなので、表示中のダイアログを名指しで閉じる手立てを
/// 呼び出し元が持てない。show ごとに1個返すこのハンドルが、その1枚だけを取り消す操作を持つ。
/// 呼び出し元の待機が打ち切られたときに、表示だけが残ることを防ぐために使う (core/ADR-0003)。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない
/// (利用者向けの入口は `KsDialogsKmp`)。
@objc(KSDInteropDialogShowHandle)
public final class KsDialogsInteropShowHandle: NSObject, Sendable {
    private let presentation: Task<Void, Never>

    init(presentation: Task<Void, Never>) {
        self.presentation = presentation
        super.init()
    }

    /// この show が表示しているダイアログを閉じ、結果を cancelled として確定させる。
    /// 結果が確定済みなら何も起こさない (結果はちょうど1回だけ有効)。
    @objc
    public func cancel() {
        presentation.cancel()
    }
}
#endif
