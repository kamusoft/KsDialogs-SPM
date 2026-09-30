#if canImport(UIKit)
import UIKit

/// 表示中のページを、優先順に並べた取得元から決める。
///
/// 優先順は「modifier の台帳 > 登録された関数 > 既定の探し方」で、上位の取得元が
/// 候補を持たない・nil を返す・エラーを投げる・空の矩形を返すときは次へ進む (core/ADR-0038)。
/// 1 回の表示の器は表示の開始時に作ったこの値を使い続けるので、登録の差し替えは次の表示から効く。
@MainActor
struct DialogCurrentPageResolver {
    /// 問い合わせる順に並べた取得元。
    let sources: [any DialogCurrentPageSource]

    /// 表示の開始時点の登録内容で組み立てる。
    static func capturingRegistration(
        ledger: DialogCurrentPageLedger = .shared
    ) -> DialogCurrentPageResolver {
        var sources: [any DialogCurrentPageSource] = [ledger]
        if let provider = DialogCurrentPage.provider {
            sources.append(DialogRegisteredCurrentPageSource(provider: provider))
        }
        sources.append(DialogDefaultCurrentPageSource())
        return DialogCurrentPageResolver(sources: sources)
    }

    /// ダイアログを出すウィンドウに属する表示中のページを決める。
    func resolve(in window: UIWindow) -> DialogCurrentPageResolution {
        var reasons: [String] = []
        for source in sources {
            switch source.lookUpPageRect(in: window) {
            case .found(let rect):
                return .resolved(rect)
            case .notFound(let reason):
                reasons.append(reason)
            }
        }
        return .unresolved(reasons: reasons)
    }
}
#endif
