#if canImport(UIKit)
import UIKit

/// 既定ローディングの内蔵コンテンツ (core/ADR-0023)。
///
/// カスタム Loading View と同じ共有経路 (コンテンツホスティング・レイアウト規則・演出) に載るため、
/// 器から見るとただの中身の View である。スタイルは表示の開始時に一度だけ受け取り、
/// 表示中は表示テキストだけが更新される。
///
/// 見えは AiForms.Maui.Dialogs の `DefaultLoading` と同じ「覆いに素のスピナーとテキストを直置き」で、
/// 中身自身は背景を持たない (背景の覆いは器が描く)。カード風の装飾が要る用途は
/// カスタム Loading View が受け持つ。
@MainActor
final class LoadingDefaultContentView: UIView {
    /// インジケータの下端とメッセージの上端の間隔。
    private static let stackSpacing: CGFloat = 20

    /// メッセージの行間。表示テキストは複数行になり得る (進捗つきではメッセージと百分率が別の行になる)
    /// ため、行が詰まって1つの塊に見えないだけの間隔を空ける。
    private static let messageLineSpacing: CGFloat = 8

    private let indicator = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private let stack: UIStackView

    init(style: LoadingStyle) {
        stack = UIStackView(arrangedSubviews: [indicator, messageLabel])
        super.init(frame: .zero)

        // 中身は覆いの上に直接置かれるため、自身は透明のままにする。
        backgroundColor = .clear

        indicator.color = style.indicatorColor
        indicator.startAnimating()

        messageLabel.backgroundColor = .clear
        messageLabel.textColor = style.messageColor
        // 覆いの上で読み取りやすいよう、内蔵コンテンツのメッセージは太字で描く。
        // 大きさと色はスタイルの指定に従い、太さは内蔵コンテンツの見えとして固定する。
        messageLabel.font = .systemFont(ofSize: CGFloat(style.messageFontSize), weight: .bold)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.isHidden = true

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Self.stackSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leftAnchor.constraint(equalTo: leftAnchor),
            stack.rightAnchor.constraint(equalTo: rightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("This View does not support instantiation from a storyboard.")
    }

    /// 表示テキストを差し替える。空文字ならメッセージの行そのものを畳む。
    ///
    /// 行間はフォーマットの結果 (改行の数) に依らずこの View が与える。
    /// フォーマット関数は表示テキストの文言だけを決め、字間・行間の見えは持たない。
    func apply(text: String) {
        messageLabel.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: messageLabel.font as Any,
                .foregroundColor: messageLabel.textColor as Any,
                .paragraphStyle: Self.messageParagraphStyle
            ]
        )
        messageLabel.isHidden = text.isEmpty
    }

    /// メッセージの段落設定。行間と中央寄せ・折り返しを与える。
    private static let messageParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = messageLineSpacing
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        return style
    }()

    /// 表示中のテキスト。観察用。
    var displayedText: String? {
        messageLabel.isHidden ? nil : messageLabel.text
    }

    /// 表示中のメッセージの文字。観察用。
    var displayedMessageFont: UIFont {
        messageLabel.font
    }

    /// 表示中のメッセージの文字色。観察用。
    var displayedMessageColor: UIColor? {
        messageLabel.textColor
    }

    /// 表示中のメッセージの行間。観察用。
    var displayedMessageLineSpacing: CGFloat {
        guard let attributedText = messageLabel.attributedText, attributedText.length > 0 else { return 0 }
        let style = attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        return style?.lineSpacing ?? 0
    }

    /// 表示中のインジケータの色。観察用。
    var displayedIndicatorColor: UIColor? {
        indicator.color
    }
}
#endif
