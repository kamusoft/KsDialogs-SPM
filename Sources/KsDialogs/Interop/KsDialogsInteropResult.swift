#if canImport(UIKit)
import Foundation

/// 互換面が返す型消去された結果。
/// 結果値は `Any` のまま運び、宣言結果型への復元は呼び出し側 (委譲元) が行う。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない
/// (利用者向けの入口は型付きの `KsDialogsKmp`)。
@objc(KSDInteropDialogResult)
public final class KsDialogsInteropResult: NSObject {
    /// completed / cancelled / error の判別。
    @objc public let kind: KsDialogsInteropResultKind
    /// completed のときの結果値。それ以外では nil。
    @objc public let value: Any?
    /// error のときの失敗理由。それ以外では nil。
    @objc public let error: NSError?

    private init(kind: KsDialogsInteropResultKind, value: Any?, error: NSError?) {
        self.kind = kind
        self.value = value
        self.error = error
        super.init()
    }

    convenience init(outcome: DialogOutcome) {
        switch outcome {
        case .completed(let value):
            // 宣言結果型と合わない報告は、完了ではなく失敗の判別で返す
            if let mismatch = value as? KsDialogsInteropResultTypeMismatch {
                self.init(error: mismatch.error)
            } else {
                self.init(kind: .completed, value: value, error: nil)
            }
        case .cancelled:
            self.init(kind: .cancelled, value: nil, error: nil)
        }
    }

    convenience init(error: any Error) {
        self.init(kind: .error, value: nil, error: error as NSError)
    }
}
#endif
