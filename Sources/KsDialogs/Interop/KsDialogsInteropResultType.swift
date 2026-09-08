#if canImport(UIKit)
import Foundation

/// 互換面へ登録するときに受け取る、その ViewModel の宣言結果型。
///
/// ObjC 面に型そのものは出せないため、名前と「その型として受け取れるか」の判定手続きの組で表す。
/// 判定手続きは登録側が用意し、報告された結果値がこの型に合うかを `complete` の時点で確かめるのに使う。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない
/// (型付きの `KsDialogsKmp` の登録では、結果型は `result:` 引数から導かれる)。
/// 中身のスレッド安全性は登録側の責務であり、この型は保証しない。
@objc(KSDInteropDialogResultType)
public final class KsDialogsInteropResultType: NSObject, @unchecked Sendable {
    /// 宣言結果型の名前。不一致を報告するときの説明に使う。
    @objc public let name: String

    private let matcher: (Any) -> Bool

    /// - Parameters:
    ///   - name: 宣言結果型の名前
    ///   - matcher: 結果値がその型として受け取れるかを返す判定手続き
    @objc(initWithName:matcher:)
    public init(name: String, matcher: @escaping (Any) -> Bool) {
        self.name = name
        self.matcher = matcher
        super.init()
    }

    /// 報告された結果値がこの型として受け取れるか。
    @objc(acceptsValue:)
    public func accepts(_ value: Any) -> Bool {
        matcher(value)
    }
}
#endif
