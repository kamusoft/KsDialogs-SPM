#if canImport(UIKit)
import UIKit

/// ViewModel のメッセージを折り返して表示する中身の View。
/// 内容の量で高さが変わるため、提示の時点でサイズが確定しているかを観察できる。
final class MessageTestContentView: UIView {
    init(message: String) {
        super.init(frame: .zero)
        let label = UILabel()
        label.numberOfLines = 0
        label.text = message
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leftAnchor.constraint(equalTo: leftAnchor),
            label.rightAnchor.constraint(equalTo: rightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("この View は storyboard からの生成に対応しない")
    }
}
#endif
