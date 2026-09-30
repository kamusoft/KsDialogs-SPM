import Foundation

/// 互換面から理由の欠けた失敗が届いたことを表す失敗。
///
/// 互換面は失敗の判別に必ず理由を添えるので、ふつうは届かない。届いた場合に、提示先の不在など
/// 別の理由を名乗らせず、理由が欠けていたことをそのまま伝えるために使う。
struct KsDialogsKmpMissingFailureReason: Error, Equatable, Sendable {}

// 失敗の説明文 (診断文言) は英語固定でローカライズしない (cross/ADR-0015)。
extension KsDialogsKmpMissingFailureReason: LocalizedError {
    var errorDescription: String? {
        "The Dialog failed without a reported reason."
    }
}
