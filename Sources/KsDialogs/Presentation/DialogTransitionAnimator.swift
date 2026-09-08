#if canImport(UIKit)
import UIKit

/// 時間つきのアニメーションを1本走らせ、その完了を待てるようにする実行部。
///
/// プリセットのフックと器のオーバーレイのフェードは、どちらもここを通る。
@MainActor
enum DialogTransitionAnimator {
    /// その時間でアニメーションを組めるか。
    ///
    /// 0・負値・NaN・無限大は演出として成立しないため、アニメーションを組まずに
    /// 最終状態へ飛ばす合図として使う (例外にもオーバーフローにもしない)。
    static func isAnimatable(_ duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0
    }

    /// 指定の時間・イージングでアニメーションを走らせ、完了するまで待つ。
    ///
    /// 時間が成立しない値なら最終状態を即座に反映して戻る。
    /// 待っている間にキャンセルされたら、アニメーションを最終状態で打ち切って戻る。
    static func run(
        duration: TimeInterval,
        timing: any UITimingCurveProvider,
        animations: @escaping () -> Void
    ) async {
        guard isAnimatable(duration) else {
            animations()
            return
        }
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        animator.addAnimations(animations)
        let boxedAnimator = UncheckedSendableBox(animator)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                animator.addCompletion { _ in continuation.resume() }
                animator.startAnimation()
            }
        } onCancel: {
            Task { @MainActor in
                let animator = boxedAnimator.value
                guard animator.state == .active else { return }
                animator.stopAnimation(false)
                animator.finishAnimation(at: .end)
            }
        }
    }
}
#endif
