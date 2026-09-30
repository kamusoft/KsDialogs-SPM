#if canImport(UIKit)
import UIKit

/// アプリが `DialogCurrentPage.provider` に登録した関数を取得元にする。
///
/// 関数は表示の開始時に捕まえたものを使い続けるため、表示中に登録を差し替えても
/// そのダイアログの基準は変わらない。
@MainActor
struct DialogRegisteredCurrentPageSource: DialogCurrentPageSource {
    private static let origin = "the registered current page provider"

    let provider: @MainActor () throws -> UIView?

    func lookUpPageRect(in window: UIWindow) -> DialogCurrentPageLookup {
        let view: UIView?
        do {
            view = try provider()
        } catch {
            return .notFound(reason: "The registered current page provider threw an error (\(error.localizedDescription)).")
        }
        guard let view else {
            return .notFound(reason: "The registered current page provider returned nil.")
        }
        return DialogCurrentPageGeometry.pageRect(of: view, in: window, origin: Self.origin)
    }
}
#endif
