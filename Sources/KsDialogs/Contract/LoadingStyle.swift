#if canImport(UIKit)
import UIKit

/// 既定ローディング (ライブラリ同梱の内蔵コンテンツ) の見た目の設定 (core/ADR-0023)。
///
/// 設定できるのは内蔵コンテンツ固有の項目だけで、器のレイアウト属性 (配置・余白・覆いの色) は
/// `DialogPlacement` / `DialogOptions` が受け持つ。重複した属性はここに置かない。
///
/// 供給経路は `KsLoading` の設定プロパティへの一括設定だけで、表示 API の引数では渡せない。
/// 器は各表示の開始時にこの値を読むため、設定の変更は次の表示から効く。
public struct LoadingStyle: Sendable {
    /// メッセージと進捗から表示テキストを組み立てる関数。
    /// 進捗が未報告のときは第2引数が nil になる。
    public typealias ProgressFormat = @Sendable (_ message: String?, _ progress: Double?) -> String

    /// 回転インジケータの色。
    public var indicatorColor: UIColor

    /// メッセージの文字の大きさ (pt)。
    public var messageFontSize: Double

    /// メッセージの文字色。
    public var messageColor: UIColor

    /// メッセージを省略して表示したときに使う文言。nil ならメッセージなしで表示する。
    public var defaultMessage: String?

    /// 表示テキストの組み立て方。既定はメッセージと百分率を改行で連ねる。
    public var progressFormat: ProgressFormat

    public init(
        indicatorColor: UIColor = .white,
        messageFontSize: Double = 14,
        messageColor: UIColor = .white,
        defaultMessage: String? = nil,
        progressFormat: @escaping ProgressFormat = LoadingStyle.defaultProgressFormat
    ) {
        self.indicatorColor = indicatorColor
        self.messageFontSize = messageFontSize
        self.messageColor = messageColor
        self.defaultMessage = defaultMessage
        self.progressFormat = progressFormat
    }

    /// ライブラリ既定の組み立て方。
    ///
    /// 進捗が未報告ならメッセージだけを返し、報告済みなら百分率 (小数点以下は四捨五入) を
    /// 改行で続ける。メッセージが無ければ百分率だけを返す。
    public static let defaultProgressFormat: ProgressFormat = { message, progress in
        let trimmedMessage = (message?.isEmpty ?? true) ? nil : message
        guard let progress else { return trimmedMessage ?? "" }
        let percentage = "\(Int((progress * 100).rounded()))%"
        guard let trimmedMessage else { return percentage }
        return "\(trimmedMessage)\n\(percentage)"
    }
}
#endif
