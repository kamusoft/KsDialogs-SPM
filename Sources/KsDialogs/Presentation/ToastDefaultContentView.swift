#if canImport(UIKit)
import UIKit

/// Toast のデフォルト View (core/ADR-0028・0032)。
///
/// カスタム Toast View と同じ共有経路 (コンテンツホスティング・レイアウト規則・演出) に載るため、
/// 器から見るとただの中身の View である。Toast の器は覆いを持たないので、
/// この View が自分でピルの地色と角丸を描く。
///
/// 見えは OS 標準 Toast の慣習に寄せた「半透明ダークグレーのピル + 白い中央寄せテキスト」で、
/// `ToastStyle` で設定できるのは地色・文字色・文字の大きさ・角丸半径だけである。
/// 余白・最大幅・寄せ・行間は内蔵コンテンツ側の固定値として持つ。
@MainActor
final class ToastDefaultContentView: UIView {
    /// ピルの上下の余白。
    private static let verticalPadding: CGFloat = 11

    /// ピルの左右の余白。
    private static let horizontalPadding: CGFloat = 22

    /// 取り付け先の幅に対するピルの最大幅の比率。
    private static let maxWidthRatio: CGFloat = 0.8

    /// 文字の大きさに対する行の高さの比率。
    private static let lineHeightRatio: CGFloat = 1.5

    private let messageLabel = UILabel()

    /// 表示するメッセージ。
    private let message: String

    /// 支援技術への通知口。
    private let announcer: any ToastAccessibilityAnnouncer

    /// 読み上げへ流したか。ウィンドウへの出入りが繰り返されても通知は1回だけにする。
    private var didAnnounce = false

    /// 取り付け先の幅に追随する最大幅の制約。
    private var maxWidthConstraint: NSLayoutConstraint?

    init(message: String, style: ToastStyle, announcer: any ToastAccessibilityAnnouncer) {
        self.message = message
        self.announcer = announcer
        super.init(frame: .zero)

        backgroundColor = style.backgroundColor
        layer.cornerRadius = CGFloat(style.cornerRadius)
        // 角丸の内側だけを塗るために丸めを効かせつつ、影は外へ落とす。
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)

        // Toast はタップで消えず、面へのタッチは背後へ素通しする (core/ADR-0031)。
        // 当たり判定は器のルート View が一括で外すため、この View 自身も入力を受け取らない。
        isUserInteractionEnabled = false
        // 表示のたびに読み上げのフォーカスが飛ばないよう、この中身は支援技術の走査対象から外す。
        // メッセージは読み上げへ通知として流す。
        accessibilityElementsHidden = true

        messageLabel.backgroundColor = .clear
        messageLabel.textColor = style.textColor
        messageLabel.font = .systemFont(ofSize: CGFloat(style.fontSize))
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.attributedText = NSAttributedString(
            string: message,
            attributes: [
                .font: messageLabel.font as Any,
                .foregroundColor: messageLabel.textColor as Any,
                .paragraphStyle: Self.paragraphStyle(fontSize: CGFloat(style.fontSize))
            ]
        )
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            messageLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            messageLabel.leftAnchor.constraint(equalTo: leftAnchor, constant: Self.horizontalPadding),
            messageLabel.rightAnchor.constraint(equalTo: rightAnchor, constant: -Self.horizontalPadding)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("This View does not support instantiation from a storyboard.")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        maxWidthConstraint?.isActive = false
        maxWidthConstraint = nil
        guard let superview else { return }
        // 最大幅は取り付け先の幅に対する比率なので、載った先が決まってから張る。
        let constraint = widthAnchor.constraint(
            lessThanOrEqualTo: superview.widthAnchor,
            multiplier: Self.maxWidthRatio
        )
        constraint.isActive = true
        maxWidthConstraint = constraint
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !didAnnounce else { return }
        didAnnounce = true
        // フォーカスを動かす通知 (screenChanged / layoutChanged) は使わない。
        announcer.post(notification: .announcement, argument: message)
    }

    /// 段落設定。中央寄せ・折り返しと、文字の大きさに比例した行の高さを与える。
    private static func paragraphStyle(fontSize: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let lineHeight = fontSize * lineHeightRatio
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return style
    }

    /// 表示中のメッセージ。観察用。
    var displayedText: String? {
        messageLabel.text
    }

    /// 表示中のメッセージの文字。観察用。
    var displayedFont: UIFont {
        messageLabel.font
    }

    /// 表示中のメッセージの文字色。観察用。
    var displayedTextColor: UIColor? {
        messageLabel.textColor
    }

    /// 表示中のピルの地色。観察用。
    var displayedBackgroundColor: UIColor? {
        backgroundColor
    }

    /// 表示中のピルの角丸半径。観察用。
    var displayedCornerRadius: CGFloat {
        layer.cornerRadius
    }
}
#endif
