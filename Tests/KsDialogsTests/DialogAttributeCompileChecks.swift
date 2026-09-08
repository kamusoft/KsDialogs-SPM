#if canImport(UIKit)
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// 利用者が書くのと同じ形の ViewModel。真偽値の結果を宣言する。
///
/// 内部シンボルの見えない面で宣言することで、利用者が自分の型を `DialogViewModel` に
/// 適合させられることまで公開面だけで示せる。
final class ConsumerDialogViewModel: DialogViewModel {
    typealias Result = Bool

    let message: String

    init(message: String) {
        self.message = message
    }
}

/// メタ属性の公開 API 形状のコンパイル検証。
///
/// 正の検証 (既存の呼び出しがそのまま通る・添付と show 引数で供給できる) は既定のビルドに含まれる。
/// 負の検証は禁止形状ごとに別のフラグへ分けてあり、**フラグを1つだけ定義したビルドが失敗すること**が
/// 期待結果になる。1回のビルドに1つの誤りしか含めないので、どの禁止形状が効いているかを個別に示せる:
///
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_VM_ATTRIBUTE'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_SHOW_OPTIONS'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_SHOW_TRANSITION'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_OPTIONS_TRANSITION'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_NONE_ARGUMENT'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_DEFAULT_DURATION'
@MainActor
enum DialogAttributeCompileChecks {
    /// メタ属性を供給しない既存の呼び出しがそのまま通る。
    static func acceptsShowWithoutPlacement(dialogs: any KsDialog) async throws {
        _ = try await dialogs.show(ConsumerDialogViewModel(message: ""))
    }

    /// placement は show の引数で供給できる。
    static func acceptsShowWithPlacement(dialogs: any KsDialog) async throws {
        _ = try await dialogs.show(
            ConsumerDialogViewModel(message: ""),
            placement: DialogPlacement(horizontalAlignment: .start, offsetX: 12)
        )
    }

    /// options と placement は中身の View への添付で供給できる。
    static func acceptsAttachmentOnContentView() {
        let contentView = DialogTestContentView()
        contentView.ksDialogOptions = DialogOptions(layoutArea: .window, isCanceledOnTouchOutside: false)
        contentView.ksDialogPlacement = DialogPlacement(verticalAlignment: .end)
    }

    #if KSDIALOGS_NEGATIVE_CHECK_VM_ATTRIBUTE
    /// ViewModel はレイアウト属性を持たない。
    /// 期待する診断: value of type 'ConsumerDialogViewModel' has no member 'proportionalWidth'
    static func rejectsLayoutAttributeOnViewModel() {
        _ = ConsumerDialogViewModel(message: "").proportionalWidth
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_SHOW_OPTIONS
    /// show に options 引数はない。
    /// 期待する診断: extra argument 'options' in call
    static func rejectsOptionsArgumentOnShow(dialogs: any KsDialog) async throws {
        _ = try await dialogs.show(ConsumerDialogViewModel(message: ""), options: DialogOptions())
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_SHOW_TRANSITION
    /// show に transition 引数はない。演出は添付だけで供給する。
    /// 期待する診断: extra argument 'transition' in call
    static func rejectsTransitionArgumentOnShow(dialogs: any KsDialog) async throws {
        _ = try await dialogs.show(ConsumerDialogViewModel(message: ""), transition: DialogTransition.none())
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_OPTIONS_TRANSITION
    /// DialogOptions はトランジション系のプロパティを持たない。
    /// 期待する診断: value of type 'DialogOptions' has no member 'transition'
    static func rejectsTransitionPropertyOnOptions() {
        _ = DialogOptions().transition
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_NONE_ARGUMENT
    /// none プリセットは引数を取らない。
    /// 期待する診断: argument passed to call that takes no arguments
    static func rejectsArgumentOnNonePreset() {
        _ = DialogTransition.none(duration: 0.25)
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_DEFAULT_DURATION
    /// プリセットの既定の時間は器の内側の値で、利用者からは参照できない。
    /// 期待する診断: 'defaultDuration' is inaccessible due to 'internal' protection level
    static func rejectsDefaultDurationConstant() {
        _ = DialogTransition.defaultDuration
    }
    #endif
}
#endif
