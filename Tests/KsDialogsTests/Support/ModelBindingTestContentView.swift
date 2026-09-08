#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// 生成された時点で ViewModel から読めたものを持ち続ける中身の View。
///
/// 「中身の生成時点で結果報告口が引けたか」「configure が設定した状態が中身へ渡ったか」を、
/// 表示された View 側から観察するために使う。
final class ModelBindingTestContentView: UIView {
    /// 生成時に ViewModel から取り出した結果報告口。引けなければ nil。
    let notifier: DialogNotifier<Bool>?

    /// 生成時に読んだ ViewModel の状態。
    let message: String

    init(notifier: DialogNotifier<Bool>?, message: String) {
        self.notifier = notifier
        self.message = message
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("この View は storyboard からの生成に対応しない")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 240, height: 120)
    }
}
#endif
