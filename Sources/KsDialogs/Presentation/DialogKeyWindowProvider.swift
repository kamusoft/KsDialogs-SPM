#if canImport(UIKit)
import UIKit

/// ダイアログの提示起点となる window を供給する。
/// アプリの window 取得手段を差し替えられるようにするための内部の継ぎ目。
protocol DialogKeyWindowProvider: Sendable {
    @MainActor var keyWindow: UIWindow? { get }
}
#endif
