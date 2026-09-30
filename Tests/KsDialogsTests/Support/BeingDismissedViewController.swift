#if canImport(UIKit)
import UIKit

/// 閉じる途中として振る舞う ViewController。
///
/// 提示先の解決は閉じる途中の ViewController の手前で辿るのをやめるため、これを提示中の提示元は
/// 「提示中のまま最前面として選ばれる」状態になる。提示機構はその提示元からの新しい提示を受け付けない。
/// 提示遷移はテスト実行環境では完走しないので、閉じる途中の状態を実際の閉鎖で作る代わりにこれを使う。
@MainActor
final class BeingDismissedViewController: UIViewController {
    override var isBeingDismissed: Bool {
        true
    }
}
#endif
