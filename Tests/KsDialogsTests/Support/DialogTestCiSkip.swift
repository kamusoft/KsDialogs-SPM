import Foundation
import Testing

/// CI 上では実行しないテストの印。
///
/// 手元では通るのに CI の実行機でだけ環境のタイミングで揺らぎ、かつ公開契約の保証そのものを
/// 固定しているわけではないテストに付ける。理由には切り分けの根拠 — 手元の反復で通ること・
/// CI での落ち方・重要な保証でないと判断した理由 — を、このファイルだけで意味が通る形で書く。
///
/// CI かどうかは、実行機が持つ汎用の環境変数ではなく **CI 側が明示的に渡す値**で判定する。
/// 汎用の変数に頼ると、同じ名前を持つ手元の環境で意図せず skip される。
/// テストの実行体はビルドを起こす側とは別プロセスで動き、`TEST_RUNNER_` を冠した環境変数だけが
/// 接頭辞を外して渡るため、CI 側は `TEST_RUNNER_KSDIALOGS_CI` として設定する。
///
/// 印はオーナーの承認 (リポジトリ設定の許可リスト `lint.ci-skip.allow`) があってはじめて置ける (cross/ADR-0021)。
/// 許可リストに対応する項目が無い印と、根拠を欠いた理由は `scripts/ci-skip-lint.py` が違反として落とす。
enum DialogTestCiSkip {
    /// CI 側が渡す環境変数の名前 (テストの実行体から見える形)。
    private static let variableName = "KSDIALOGS_CI"

    /// CI 上での実行か。
    static var isRunningOnCi: Bool {
        ProcessInfo.processInfo.environment[variableName] == "1"
    }
}

extension Trait where Self == ConditionTrait {
    /// CI 上でだけこのテストを実行しない。
    ///
    /// - Parameter reason: 切り分けの根拠。skip の記録としてそのまま残る
    static func skipOnCi(_ reason: String) -> Self {
        .disabled(
            if: DialogTestCiSkip.isRunningOnCi,
            Comment(rawValue: "CI 上では実行しない: \(reason)")
        )
    }
}
