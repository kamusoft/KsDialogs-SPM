#if canImport(UIKit)
import Foundation

/// 互換面の View へ渡す結果報告口。
/// 結果値は `Any` で受け取り、ちょうど1回だけ確定する保証は Native 側の結果チャネルが持つ
/// (互換面はそれを素通しする)。
///
/// 委譲元は結果値の型を復元できないため、登録時に受け取った宣言結果型で
/// 報告の時点で値を確かめ、合わない報告は完了ではなく失敗として返す (kmp/ADR-0002)。
///
/// この型は KMP cinterop 委譲専用の面であり、アプリコードから直接使用しない
/// (利用者向けの結果報告口は型付きの `DialogNotifier`)。
@objc(KSDInteropDialogNotifier)
public final class KsDialogsInteropNotifier: NSObject {
    private let resultChannel: DialogResultChannel
    private let resultType: KsDialogsInteropResultType

    init(resultChannel: DialogResultChannel, resultType: KsDialogsInteropResultType) {
        self.resultChannel = resultChannel
        self.resultType = resultType
        super.init()
    }

    /// 結果値つきで完了を報告する。
    /// 宣言結果型として受け取れない値だった場合は、cancelled に化けさせず失敗として確定させる。
    @objc(completeWithValue:)
    public func complete(_ value: Any) {
        guard resultType.accepts(value) else {
            resultChannel.settle(
                .completed(
                    KsDialogsInteropResultTypeMismatch(
                        expected: resultType.name,
                        actual: String(describing: type(of: value))
                    )
                )
            )
            return
        }
        resultChannel.settle(.completed(value))
    }

    /// キャンセルを報告する。
    @objc
    public func cancel() {
        resultChannel.settle(.cancelled)
    }
}
#endif
