#if canImport(UIKit)
import UIKit

/// Toast の一括設定 (core/ADR-0032)。
///
/// 項目は適用範囲で2種に分かれる。
///
/// - **視覚項目** (`backgroundColor` / `textColor` / `fontSize` / `cornerRadius`) は
///   ライブラリ同梱のデフォルト View にだけ効き、カスタム Toast View には効かない
/// - **既定値項目** (`defaultDuration` / `defaultPlacement`) はデフォルト・カスタムを問わず
///   すべての Toast に効く (表示 API で該当引数・添付を省略したときの既定になる)
///
/// 供給経路は `KsToast` の設定プロパティへの一括設定だけで、表示 API の引数では渡せない。
/// 器は各表示の受理時にこの値を読むため、設定の変更は次の表示から効く。
/// 色を含むため KMP 共有コードからは設定できず、各 OS 側で設定する。
public struct ToastStyle: Sendable {
    /// デフォルト View のピルの背景色。
    public var backgroundColor: UIColor

    /// デフォルト View のメッセージの文字色。
    public var textColor: UIColor

    /// デフォルト View のメッセージの文字の大きさ (pt)。
    public var fontSize: Double

    /// デフォルト View のピルの角丸半径 (pt)。複数行になっても変わらない固定値として扱う。
    public var cornerRadius: Double

    /// duration を省略した表示に使うミリ秒。0 以下を設定した場合は内蔵既定 (1500) へ丸められる。
    public var defaultDuration: Int

    /// アプリ全体の既定配置。nil なら Toast の契約既定値 (可視領域の下部中央 + 上方向オフセット)。
    public var defaultPlacement: DialogPlacement?

    /// ライブラリが持つ既定 duration (ミリ秒)。`defaultDuration` が成立しないときの最後の拠り所。
    public static let builtinDefaultDuration = 1500

    public init(
        backgroundColor: UIColor = ToastStyle.builtinBackgroundColor,
        textColor: UIColor = .white,
        fontSize: Double = 14,
        cornerRadius: Double = 22,
        defaultDuration: Int = ToastStyle.builtinDefaultDuration,
        defaultPlacement: DialogPlacement? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
        self.defaultDuration = defaultDuration
        self.defaultPlacement = defaultPlacement
    }

    /// デフォルト View のピルの既定の地色。OS 慣習に寄せた半透明のダークグレー。
    public static let builtinBackgroundColor = UIColor(
        red: 0x32 / 255,
        green: 0x32 / 255,
        blue: 0x32 / 255,
        alpha: 0.92
    )
}
#endif
