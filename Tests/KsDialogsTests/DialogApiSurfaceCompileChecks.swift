#if canImport(UIKit)
import SwiftUI
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// 結果型を宣言しない、利用者が書くのと同じ形の ViewModel。
/// 契約の既定 (core/ADR-0012) により、この ViewModel の結果は真偽値になる。
final class ConsumerDefaultResultDialogViewModel: DialogViewModel {
    let message: String

    init(message: String) {
        self.message = message
    }
}

/// カスタム結果型を宣言する、利用者が書くのと同じ形の ViewModel。
final class ConsumerTextDialogViewModel: DialogViewModel {
    typealias Result = String

    let prompt: String

    init(prompt: String) {
        self.prompt = prompt
    }
}

/// 追加された公開 API 形状のコンパイル検証。
///
/// SwiftUI 登録・インライン show (UIView / SwiftUI)・添付 DSL・結果型の省略形について、
/// **型注釈を足さずに書けること**を既定のビルドの中で確かめる。
/// 検証はコンパイルが通ること自体であり、実行時の挙動は別のテストが受け持つ。
@MainActor
enum DialogApiSurfaceCompileChecks {
    // MARK: 結果型の省略形

    /// 結果型を宣言しない ViewModel の結果報告口は真偽値に型付く。
    static func notifierDefaultsToBool(registry: DialogViewRegistry) {
        registry.register(ConsumerDefaultResultDialogViewModel.self) { _, notifier in
            let notifier: DialogNotifier<Bool> = notifier
            notifier.complete(true)
            return DialogTestContentView()
        }
    }

    /// 結果型を宣言しない ViewModel の show は真偽値の結果を返す。
    static func showDefaultsToBoolResult(dialogs: any KsDialog) async throws {
        let result: DialogResult<Bool> = try await dialogs.show(
            ConsumerDefaultResultDialogViewModel(message: "")
        )
        _ = result
    }

    // MARK: SwiftUI 登録

    /// SwiftUI の View を返す factory で登録できる。
    static func registersSwiftUIContent(registry: DialogViewRegistry) {
        registry.register(ConsumerDefaultResultDialogViewModel.self) { viewModel, notifier in
            VStack {
                Text(viewModel.message)
                Button("OK") { notifier.complete(true) }
            }
        }
    }

    /// カスタム結果型の ViewModel も SwiftUI の中身で登録できる。
    static func registersSwiftUIContentWithCustomResult(registry: DialogViewRegistry) {
        registry.register(ConsumerTextDialogViewModel.self) { viewModel, notifier in
            Button(viewModel.prompt) { notifier.complete("入力") }
        }
    }

    /// 従来 View 系の登録は同名のまま通る。
    static func registersUIViewContent(registry: DialogViewRegistry) {
        registry.register(ConsumerDefaultResultDialogViewModel.self) { _, _ in
            DialogTestContentView()
        }
    }

    // MARK: インライン show

    /// UIView を返す factory を show へ直接渡せる。
    static func showsInlineUIViewContent(dialogs: any KsDialog) async throws {
        let result: DialogResult<Bool> = try await dialogs.show(
            ConsumerDefaultResultDialogViewModel(message: "")
        ) { _, _ in
            DialogTestContentView()
        }
        _ = result
    }

    /// SwiftUI の View を返す factory を show へ直接渡せる。
    static func showsInlineSwiftUIContent(dialogs: any KsDialog) async throws {
        let result: DialogResult<Bool> = try await dialogs.show(
            ConsumerDefaultResultDialogViewModel(message: "")
        ) { viewModel, notifier in
            VStack {
                Text(viewModel.message)
                Button("OK") { notifier.complete(true) }
            }
        }
        _ = result
    }

    /// インライン show にも placement を渡せる (意味は登録済み show と同じ)。
    static func showsInlineContentWithPlacement(dialogs: any KsDialog) async throws {
        _ = try await dialogs.show(
            ConsumerDefaultResultDialogViewModel(message: ""),
            placement: DialogPlacement(verticalAlignment: .end)
        ) { _, _ in
            DialogTestContentView()
        }
        _ = try await dialogs.show(
            ConsumerTextDialogViewModel(prompt: ""),
            placement: DialogPlacement(verticalAlignment: .end)
        ) { viewModel, notifier in
            Button(viewModel.prompt) { notifier.complete("入力") }
        }
    }

    // MARK: SwiftUI 添付 DSL

    /// options と placement は SwiftUI の中身への添付で供給できる。
    static func attachesAttributesToSwiftUIContent(registry: DialogViewRegistry) {
        registry.register(ConsumerDefaultResultDialogViewModel.self) { viewModel, notifier in
            Button(viewModel.message) { notifier.complete(true) }
                .ksDialogOptions(DialogOptions(layoutArea: .window, isCanceledOnTouchOutside: false))
                .ksDialogPlacement(DialogPlacement(verticalAlignment: .end))
        }
    }

    // MARK: トランジション添付面

    /// 出入りの演出は従来 View 系の添付面で供給でき、フックは省略できる。
    static func attachesTransitionToContentView() {
        let contentView = DialogTestContentView()
        contentView.ksDialogTransition = DialogTransition(
            presentation: { hostView in hostView.alpha = 1 },
            dismissal: { hostView in hostView.alpha = 0 },
            overlayDuration: 0.3
        )
        contentView.ksDialogTransition = DialogTransition(presentation: { _ in })
        contentView.ksDialogTransition = DialogTransition(dismissal: { _ in })
        let attached: DialogTransition? = contentView.ksDialogTransition
        _ = attached?.presentation
        _ = attached?.dismissal
        _ = attached?.overlayDuration
    }

    /// 出入りの演出は SwiftUI の中身への添付でも供給できる。
    static func attachesTransitionToSwiftUIContent(registry: DialogViewRegistry) {
        registry.register(ConsumerDefaultResultDialogViewModel.self) { viewModel, notifier in
            Button(viewModel.message) { notifier.complete(true) }
                .ksDialogTransition(DialogTransition.slide(from: .leading))
        }
    }

    /// プリセットは引数なしでも、時間とイージングを指定しても呼べる。
    static func buildsTransitionPresets() {
        let presets: [DialogTransition] = [
            .fade(),
            .fade(duration: 0.4),
            .fade(duration: 0.4, easing: .standard),
            .slide(from: .bottom),
            .slide(from: .trailing, duration: 0.4, easing: UICubicTimingParameters(animationCurve: .easeOut)),
            .zoom(),
            .zoom(duration: 0.4, easing: .standard),
            .none()
        ]
        _ = presets
    }

    /// 方向はレイアウト方向に追随する2つと物理方向の2つを持つ。
    static func namesTransitionEdges() {
        let edges: [DialogTransitionEdge] = [.top, .bottom, .leading, .trailing]
        _ = edges
    }
}
#endif
