#if canImport(UIKit)
import Foundation

/// 合流1件の身分証を運ぶハンドル。
///
/// 互換面は Swift の値型 (`LoadingUseToken`) をそのまま ObjC 表現に出せないため、
/// 開始のときに1個返すこのハンドルが、その1件の終了と進捗報告の宛先になる。
/// 旧世代のハンドルで終了・報告を求めても、状態の正がそれを捨てる (core/ADR-0024)。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない
/// (利用者向けの入口は `Loading` と `KsLoadingKmp`)。
@objc(KSDInteropLoadingUseHandle)
public final class KsDialogsInteropLoadingUseHandle: NSObject, Sendable {
    /// この開始が属する合流1件の身分証。
    let token: LoadingUseToken

    init(token: LoadingUseToken) {
        self.token = token
        super.init()
    }
}
#endif
