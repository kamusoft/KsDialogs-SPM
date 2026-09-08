#if canImport(UIKit)
import UIKit

/// ウィンドウに載った状態での初回のレイアウトパスの最中に、自分自身へメタ属性を添付する中身の View。
///
/// 宣言的 UI からの供給 (値が届くのがレイアウトパスの中になる機構) を模した供給元で、
/// 「View の生成後・画面に載せたあとの初回レイアウトパスの完了前」に書き換わる添付を作るために使う。
/// ウィンドウに載る前の暫定のレイアウトでは供給しないため、
/// 提示より前に固定してしまう実装ではこの供給を取りこぼす。
final class LateAttachingContentView: UIView {
    private let contentSize: CGSize
    private let attachDuringLayout: (LateAttachingContentView) -> Void

    /// レイアウトパスの中で添付を行った回数。1回だけ供給したことの確認に使う。
    private(set) var attachCount = 0

    /// - Parameters:
    ///   - contentSize: 内容サイズとして主張する大きさ
    ///   - attachDuringLayout: ウィンドウに載った状態での初回のレイアウトパスの中で1度だけ呼ばれる添付処理
    init(
        contentSize: CGSize,
        attachDuringLayout: @escaping (LateAttachingContentView) -> Void
    ) {
        self.contentSize = contentSize
        self.attachDuringLayout = attachDuringLayout
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("この View は storyboard からの生成に対応しない")
    }

    override var intrinsicContentSize: CGSize {
        contentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil, attachCount == 0 else { return }
        attachCount += 1
        attachDuringLayout(self)
    }
}
#endif
