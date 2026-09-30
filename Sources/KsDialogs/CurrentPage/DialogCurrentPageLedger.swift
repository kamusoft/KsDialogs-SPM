#if canImport(UIKit)
import UIKit

/// 宣言的 UI の modifier で「現在ページ」を名乗った View の台帳。
///
/// 台帳の規則は Android の Compose 版 modifier と同じ (core/ADR-0038):
///
/// 1. 名乗った View は画面 (ウィンドウ) に載っている間だけ台帳に載る。外れたら台帳から外れ、
///    残りの候補で決め直す
/// 2. 問い合わせでは、ダイアログを出すウィンドウと別のウィンドウに属するもの、
///    ウィンドウと重ならない矩形 (隣のページなど画面外に置かれたもの) を候補から外す。
///    iOS ではさらに、ウィンドウに載っていても画面に表示されていないもの
///    (祖先が非表示、または祖先の不透明度が 0) も外す
/// 3. 候補の矩形が入れ子になっていれば内側 (小さい方) を採る
/// 4. それ以外は最後に画面へ載ったものを採る
/// 5. 候補が無ければ見つからなかった扱いにし、次の取得元へ進む
@MainActor
final class DialogCurrentPageLedger: DialogCurrentPageSource {
    /// modifier が既定で書き込む台帳。
    static let shared = DialogCurrentPageLedger()

    private static let origin = "a view marked with markAsDialogCurrentPage()"

    /// 台帳の 1 行。View は弱参照で持ち、解放された行は次の操作で掃除する。
    private struct Entry {
        weak var view: UIView?
        /// 画面へ載った順番。大きいほど新しい。
        let order: Int
    }

    private var entries: [Entry] = []
    private var nextOrder = 0

    /// 台帳に載っている View の数 (解放済みの行は数えない)。
    var attachedViewCount: Int {
        entries.filter { $0.view != nil }.count
    }

    /// View が画面へ載ったことを記録する。載り直した View は最新の順番で記録し直す。
    func attach(_ view: UIView) {
        removeEntries(for: view)
        entries.append(Entry(view: view, order: nextOrder))
        nextOrder += 1
    }

    /// View が画面から外れたことを記録する。
    func detach(_ view: UIView) {
        removeEntries(for: view)
    }

    func lookUpPageRect(in window: UIWindow) -> DialogCurrentPageLookup {
        entries.removeAll { $0.view == nil }
        let candidates: [(rect: CGRect, order: Int)] = entries.compactMap { entry in
            guard let view = entry.view,
                  Self.isShownOnScreen(view),
                  case .found(let rect) = DialogCurrentPageGeometry.pageRect(of: view, in: window, origin: Self.origin)
            else { return nil }
            return (rect, entry.order)
        }
        // 別の候補を内側に抱えている候補は外側なので外す。同じ矩形どうしはどちらも残し、順番で決める。
        let innermost = candidates.filter { candidate in
            !candidates.contains { other in
                other.rect != candidate.rect && candidate.rect.contains(other.rect)
            }
        }
        guard let chosen = innermost.max(by: { $0.order < $1.order }) else {
            return .notFound(reason: "No view marked with markAsDialogCurrentPage() is placed in the window presenting the dialog.")
        }
        return .found(chosen.rect)
    }

    /// View が画面に表示されているか。自分か祖先のどれかが非表示 (`isHidden`)、または
    /// 不透明度が実質 0 なら表示されていない扱いにする。
    ///
    /// SwiftUI の `TabView` はタブを切り替えるとき、去るタブの画面を切り替えの演出が終わるまで
    /// ウィンドウに残す (iOS 26 の実測で約 0.7 秒)。その間、去るタブの画面は不透明度 0 へ向かう
    /// 演出中で、`alpha` (演出の行き先の値) は既に 0 になっている。来るタブの画面は `alpha` が 1 で、
    /// 見た目 (presentation layer) だけが 0 から上がっていく。演出中の見た目ではなく行き先の値で
    /// 判定することで、去るタブの印を外し、来るタブの印を残す。閾値は UIKit のタッチ判定
    /// (`hitTest`) が不透明度 0.01 未満の View を見えないものとして扱うのに合わせる。
    private static func isShownOnScreen(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let ancestor = current {
            if ancestor.isHidden || ancestor.alpha < 0.01 {
                return false
            }
            current = ancestor.superview
        }
        return true
    }

    private func removeEntries(for view: UIView) {
        entries.removeAll { $0.view == nil || $0.view === view }
    }
}
#endif
