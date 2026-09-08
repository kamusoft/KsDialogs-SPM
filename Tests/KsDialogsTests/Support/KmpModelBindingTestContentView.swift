#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// 生成された時点で KMP 面のアクセサから引けた結果報告口を持ち続ける中身の View。
///
/// 共有コードの ViewModel は結果型を宣言しないため、報告口の型は登録で指定した型引数で決まる。
final class KmpModelBindingTestContentView<Result: Sendable>: UIView {
    /// 生成時に KMP 面のアクセサから取り出した結果報告口。引けなければ nil。
    let notifier: DialogNotifier<Result>?

    init(notifier: DialogNotifier<Result>?) {
        self.notifier = notifier
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
