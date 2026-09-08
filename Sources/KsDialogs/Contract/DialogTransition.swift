#if canImport(UIKit)
import Foundation
import UIKit

/// ダイアログの出入りの演出 (core/ADR-0017)。
///
/// 中身の定義へ添付すると、器は出現時に `presentation`、閉鎖時に `dismissal` を呼び、
/// その完了を待ってから次へ進む。フックはどちらも省略でき、省略した側には器の既定の
/// クロスフェードが適用される。指定した側では既定は実行されない (置き換え)。
///
/// フックが受け取るのは中身のホスト View で、宣言的 UI の中身では SwiftUI を包む View になる。
/// 背景の覆いはホスト View の兄弟レイヤとして器が常に扱うため、フックの対象にならない。
/// 覆いのフェード時間は `overlayDuration` に従う (省略時は器の既定値)。
///
/// フックが有限時間で完了することは利用者の責務で、器はタイムアウトを設けない。
/// フックが投げた失敗は演出の失敗として吸収され、ダイアログの結果には影響しない。
public struct DialogTransition: Sendable {
    /// 演出の実体。中身のホスト View を受け取り、演出が終わったら戻る。
    public typealias Hook = @MainActor @Sendable (UIView) async throws -> Void

    /// 出現時の演出。nil なら器の既定が使われる。
    public let presentation: Hook?

    /// 閉鎖時の演出。nil なら器の既定が使われる。
    public let dismissal: Hook?

    /// 背景の覆いのフェード時間。nil なら器の既定値になる。
    public let overlayDuration: TimeInterval?

    /// 添付された組を見分けるための印。値そのものは意味を持たない。
    let identity = UUID()

    /// - Parameters:
    ///   - presentation: 出現時の演出
    ///   - dismissal: 閉鎖時の演出
    ///   - overlayDuration: 背景の覆いのフェード時間
    public init(
        presentation: Hook? = nil,
        dismissal: Hook? = nil,
        overlayDuration: TimeInterval? = nil
    ) {
        self.presentation = presentation
        self.dismissal = dismissal
        self.overlayDuration = overlayDuration
    }
}

// MARK: - プリセット

public extension DialogTransition {
    /// 透明度で出入りする演出。
    /// - Parameters:
    ///   - duration: 片道の時間。成立しない値 (0・負値・NaN・無限大) では演出なしで即完了する
    ///   - easing: 時間に対する進み方
    @MainActor
    static func fade(
        duration: TimeInterval = 0.25,
        easing: any UITimingCurveProvider = .standard
    ) -> DialogTransition {
        let timing = UncheckedSendableBox(easing)
        return DialogTransition(
            presentation: { view in
                guard DialogTransitionAnimator.isAnimatable(duration) else { return }
                view.alpha = 0
                await DialogTransitionAnimator.run(duration: duration, timing: timing.value) {
                    view.alpha = 1
                }
            },
            dismissal: { view in
                guard DialogTransitionAnimator.isAnimatable(duration) else { return }
                await DialogTransitionAnimator.run(duration: duration, timing: timing.value) {
                    view.alpha = 0
                }
            },
            overlayDuration: duration
        )
    }

    /// 指定した辺から滑り込み、同じ辺へ滑り出す演出。
    /// - Parameters:
    ///   - edge: 出入り口になる辺
    ///   - duration: 片道の時間。成立しない値では演出なしで即完了する
    ///   - easing: 時間に対する進み方
    @MainActor
    static func slide(
        from edge: DialogTransitionEdge,
        duration: TimeInterval = 0.25,
        easing: any UITimingCurveProvider = .standard
    ) -> DialogTransition {
        let timing = UncheckedSendableBox(easing)
        return DialogTransition(
            presentation: { view in
                guard DialogTransitionAnimator.isAnimatable(duration) else { return }
                view.transform = Self.slideTransform(for: edge, of: view)
                await DialogTransitionAnimator.run(duration: duration, timing: timing.value) {
                    view.transform = .identity
                }
            },
            dismissal: { view in
                guard DialogTransitionAnimator.isAnimatable(duration) else { return }
                let outward = Self.slideTransform(for: edge, of: view)
                await DialogTransitionAnimator.run(duration: duration, timing: timing.value) {
                    view.transform = outward
                }
            },
            overlayDuration: duration
        )
    }

    /// 少し縮んだ状態から等倍へ広がり、同じ倍率へ縮んで消える演出。
    /// - Parameters:
    ///   - duration: 片道の時間。成立しない値では演出なしで即完了する
    ///   - easing: 時間に対する進み方
    @MainActor
    static func zoom(
        duration: TimeInterval = 0.25,
        easing: any UITimingCurveProvider = .standard
    ) -> DialogTransition {
        let timing = UncheckedSendableBox(easing)
        return DialogTransition(
            presentation: { view in
                guard DialogTransitionAnimator.isAnimatable(duration) else { return }
                view.transform = Self.zoomTransform
                view.alpha = 0
                await DialogTransitionAnimator.run(duration: duration, timing: timing.value) {
                    view.transform = .identity
                    view.alpha = 1
                }
            },
            dismissal: { view in
                guard DialogTransitionAnimator.isAnimatable(duration) else { return }
                await DialogTransitionAnimator.run(duration: duration, timing: timing.value) {
                    view.transform = Self.zoomTransform
                    view.alpha = 0
                }
            },
            overlayDuration: duration
        )
    }

    /// 中身の演出を持たない組。覆いだけが器の既定の時間でフェードする。
    @MainActor
    static func none() -> DialogTransition {
        DialogTransition(
            presentation: { _ in },
            dismissal: { _ in },
            overlayDuration: defaultDuration
        )
    }
}

// MARK: - 器の内側で使う既定値

extension DialogTransition {
    /// プリセットが引数を省略したときの時間。
    ///
    /// 公開面には出さない値なので、プリセットの既定引数には同じ 0.25 を直接書いてある
    /// (公開関数の既定引数式は呼び出し側へ展開されるため、内部の定数を参照できない)。
    /// 器の既定の覆いのフェード時間もこの値に揃える。
    static let defaultDuration: TimeInterval = 0.25
}

private extension DialogTransition {
    /// ズームの開始・終了倍率。
    static var zoomTransform: CGAffineTransform {
        CGAffineTransform(scaleX: 0.8, y: 0.8)
    }

    /// 指定の辺の外側まで View を送り出す平行移動。
    ///
    /// 送り出す距離は、View が載っている面の縁を越えるところまでを取る。
    /// 面が分からないうちは View 自身の大きさを距離に使う。
    @MainActor
    static func slideTransform(for edge: DialogTransitionEdge, of view: UIView) -> CGAffineTransform {
        let frame = view.frame
        let containerSize = view.superview?.bounds.size ?? frame.size
        switch resolvedEdge(edge, in: view) {
        case .top:
            return CGAffineTransform(translationX: 0, y: -frame.maxY)
        case .bottom:
            return CGAffineTransform(translationX: 0, y: containerSize.height - frame.minY)
        case .leading:
            return CGAffineTransform(translationX: -frame.maxX, y: 0)
        case .trailing:
            return CGAffineTransform(translationX: containerSize.width - frame.minX, y: 0)
        }
    }

    /// レイアウト方向に追随する辺を、画面上の辺へ読み替える。
    /// 右から左へ読む環境では leading が右、trailing が左になる。
    @MainActor
    static func resolvedEdge(_ edge: DialogTransitionEdge, in view: UIView) -> DialogTransitionEdge {
        guard view.effectiveUserInterfaceLayoutDirection == .rightToLeft else { return edge }
        switch edge {
        case .leading:
            return .trailing
        case .trailing:
            return .leading
        case .top, .bottom:
            return edge
        }
    }
}
#endif
