#if canImport(UIKit)
import UIKit
import os

/// 出入りの演出を実行する部品 (core/ADR-0017)。
///
/// 演出の実効値の固定 (フックの解決)、フックの起動と失敗の吸収、
/// 中身とは別のレイヤに敷いた覆いのフェードを受け持つ。
/// 器はこの部品を持ち、提示・退出のそれぞれで対応する局面を走らせる。
@MainActor
final class DialogTransitionRunner {
    /// 器が既定で使う出入りの演出 (core/ADR-0017)。
    /// 添付がない側のフックと、覆いのフェード時間の既定値がここから決まる。
    static let defaultTransition = DialogTransition.fade()

    /// 開発中にフックの完了忘れを気づけるようにするための警告までの時間。
    /// 契約上の上限ではなく、打ち切りもしない。
    private static let hookWarningThreshold: Duration = .seconds(5)

    /// 演出まわりの不具合を知らせるための記録口。
    private static let logger = Logger(subsystem: "jp.kamusoft.ksdialogs", category: "transition")

    /// 背景の覆い。中身の兄弟として敷き、中身とは独立にフェードする。
    private(set) lazy var overlayView: UIView = {
        let overlay = UIView()
        // タップは覆いを素通りして器のジェスチャへ届かせる。
        overlay.isUserInteractionEnabled = false
        overlay.alpha = 0
        return overlay
    }()

    /// フックが受け取る中身のホスト View。
    private let contentView: UIView

    /// 実効値と同じ時点で固定された出入りの演出。固定前は nil。
    private(set) var resolvedTransition: DialogTransition?

    /// 固定された覆いのフェード時間。
    private(set) var resolvedOverlayDuration: TimeInterval = DialogTransition.defaultDuration

    /// - Parameter contentView: 演出のフックへ渡す中身のホスト View
    init(contentView: UIView) {
        self.contentView = contentView
    }

    /// 覆いを器の View 全面に敷く。
    /// 覆いと中身を兄弟のレイヤに分けることで、覆いのフェードが中身を巻き込まない (core/ADR-0017)。
    func installOverlay(in containerView: UIView, color: UIColor) {
        overlayView.backgroundColor = color
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            overlayView.leftAnchor.constraint(equalTo: containerView.leftAnchor),
            overlayView.rightAnchor.constraint(equalTo: containerView.rightAnchor)
        ])
    }

    /// 覆いの色を実効値へ合わせる。
    func applyOverlayColor(_ color: UIColor) {
        overlayView.backgroundColor = color
    }

    /// レイアウトの実効値と同じ時点で出入りの演出を固定する (core/ADR-0017)。
    /// 添付されていない側のフックと、省略された覆いの時間には器の既定が入る。
    /// - Parameter attached: 中身へ添付された演出の組。添付がなければ nil
    func settleSnapshot(attached: DialogTransition?) {
        resolvedTransition = DialogTransition(
            presentation: attached?.presentation ?? Self.defaultTransition.presentation,
            dismissal: attached?.dismissal ?? Self.defaultTransition.dismissal,
            overlayDuration: attached?.overlayDuration ?? Self.defaultTransition.overlayDuration
        )
        resolvedOverlayDuration = resolvedTransition?.overlayDuration ?? DialogTransition.defaultDuration
    }

    /// 出現の演出と覆いの出現フェードを並行して走らせ、両方の完了を待つ。
    ///
    /// 中身を見せる操作 (`revealContent`) と出現フックの呼び出しは**同じ同期区間**に置く。
    /// 覆いのフェードは別の仕事へ切り分けるので実際の開始はこの区間の後になるが、
    /// フックは `await` で直接呼ぶため、フックが最初に置く状態 (滑り込みなら画面外の位置) までが
    /// この区間の中で反映される。間に描画を挟ませないことで、フックが効く前の
    /// 最終位置が1フレーム見える現象を構造的に防ぐ (core/ADR-0017)。
    ///
    /// これが成り立つのは `DialogTransition.Hook` が `@MainActor` で宣言されているためで、
    /// 同じアクター上への直接の `await` は最初の中断点まで同期実行される。中断のない開始を
    /// 明示できる `Task.immediate` は対象 OS の下限では使えないため、この性質に依存する。
    /// - Parameter revealContent: 中身を見せる操作。覆いのフェードを仕込んだ直後に呼ばれる
    func runPresentationPhase(revealContent: @MainActor () -> Void) async {
        async let overlay: Void = self.runOverlayFade(toVisible: true)
        revealContent()
        await runHook(resolvedTransition?.presentation, phase: "presentation")
        _ = await overlay
    }

    /// 退出の演出と覆いの消滅フェードを並行して走らせ、両方の完了を待つ。
    func runDismissalPhase() async {
        async let overlay: Void = self.runOverlayFade(toVisible: false)
        async let hook: Void = self.runHook(self.resolvedTransition?.dismissal, phase: "dismissal")
        _ = await (overlay, hook)
    }

    /// 覆いを出現・消滅させる。今の濃さから目標の濃さへ動かすので、
    /// 途中で打ち切られた出現の続きからでも滑らかに消せる。
    private func runOverlayFade(toVisible: Bool) async {
        await DialogTransitionAnimator.run(
            duration: resolvedOverlayDuration,
            timing: .standard
        ) { [overlayView] in
            overlayView.alpha = toVisible ? 1 : 0
        }
    }

    /// フックを1本走らせる。
    ///
    /// フックの失敗は演出の失敗であって結果の失敗ではないため、記録だけ残して先へ進む。
    /// 完了しないフックはダイアログを撤去させないので、開発中は一定時間で警告を出す。
    private func runHook(_ hook: DialogTransition.Hook?, phase: String) async {
        guard let hook else { return }
        let watchdog = startHookWarningWatchdog(phase: phase)
        defer { watchdog?.cancel() }
        do {
            try await hook(contentView)
        } catch is CancellationError {
            // 脱出口で取り消した分。演出を捨てて先へ進むのが意図した動きなので記録しない。
        } catch {
            Self.logger.warning(
                "The Dialog \(phase, privacy: .public) hook failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// 開発中だけ、長すぎるフックに警告を出す見張りを立てる。打ち切りはしない。
    private func startHookWarningWatchdog(phase: String) -> Task<Void, Never>? {
        #if DEBUG
        return Task { @MainActor in
            try? await Task.sleep(for: Self.hookWarningThreshold)
            guard !Task.isCancelled else { return }
            Self.logger.warning(
                "The Dialog \(phase, privacy: .public) hook did not complete. Completing the hook is the caller's responsibility."
            )
        }
        #else
        return nil
        #endif
    }
}
#endif
