#if canImport(UIKit)
import UIKit

/// factory が作った中身の内部表現。
///
/// 中身を書く技術 (従来 View 系 / SwiftUI) はこの1本の表現に収束させ、
/// 提示・結果・レイアウトの経路を技術ごとに分けない (core/ADR-0011)。
struct DialogContent {
    /// 器に載せる View。SwiftUI の中身はホストの View を包んだものになる。
    let view: UIView

    /// 中身を所有する ViewController。SwiftUI の中身のホストで、従来 View 系では nil。
    /// 器はこれを child containment に組み込んで保持し、閉鎖時に外す。
    let host: UIViewController?

    /// 従来 View 系の中身。
    init(view: UIView) {
        self.view = view
        host = nil
    }

    /// ホストを伴う中身。
    init(view: UIView, host: UIViewController) {
        self.view = view
        self.host = host
    }
}
#endif
