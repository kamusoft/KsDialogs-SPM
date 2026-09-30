#if canImport(UIKit)
import UIKit

/// `markAsDialogCurrentPage()` が名乗らせた枠と同じ矩形に敷く、見えない UIKit の View。
///
/// ウィンドウへの出入りをそのまま台帳への出入りにする。入力もアクセシビリティも持たない。
final class DialogCurrentPageMarkerView: UIView {
    private let ledger: DialogCurrentPageLedger

    init(ledger: DialogCurrentPageLedger) {
        self.ledger = ledger
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("This view does not support instantiation from a storyboard.")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            ledger.attach(self)
        } else {
            ledger.detach(self)
        }
    }
}
#endif
