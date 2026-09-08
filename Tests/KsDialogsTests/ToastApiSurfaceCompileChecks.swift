#if canImport(UIKit)
import SwiftUI
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// カスタム Toast の表示に使う、利用者が書くのと同じ形の ViewModel。
final class ConsumerToastViewModel: ToastViewModel {
    let title: String

    init(title: String) {
        self.title = title
    }
}

/// configure から状態を設定する、利用者が書くのと同じ形の ViewModel。
/// 状態の変更は UI スレッドに限るため MainActor に閉じる。
@MainActor
final class ConsumerMutableToastViewModel: ToastViewModel {
    var title: String

    nonisolated init(title: String = "保存しました") {
        self.title = title
    }
}

/// Toast の公開 API 形状のコンパイル検証。
///
/// メッセージ入口の各省略形、duration と placement の引数、スタイルの一括設定、
/// UIKit / SwiftUI 両系統の登録、インライン factory 表示が、**型注釈を足さずに書けること**を
/// 既定のビルドの中で確かめる。検証はコンパイルが通ること自体であり、
/// 実行時の挙動は別のテストが受け持つ。
///
/// 負の検証 (fire-and-forget に無い呼び出し面が漏れていないこと) は禁止形状ごとに
/// 別のフラグへ分けてあり、**フラグを1つだけ定義したビルドが失敗すること**が期待結果になる:
///
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_TOAST_HIDE'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_TOAST_SHOW_RESULT'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_TOAST_SHOW_STYLE'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_TOAST_OPTIONS'
@MainActor
enum ToastApiSurfaceCompileChecks {
    // MARK: メッセージ入口

    /// メッセージ入口は duration と placement をそれぞれ省略して書ける。
    static func TS_IO_01_showsMessageWithOptionalArguments(toast: any KsToast) {
        toast.show(message: "保存しました")
        toast.show(message: "保存しました", duration: 2000)
        toast.show(message: "保存しました", duration: nil)
        toast.show(
            message: "保存しました",
            duration: 2000,
            placement: DialogPlacement(verticalAlignment: .start)
        )
    }

    // MARK: 一括設定

    /// 見た目・既定 duration・アプリ既定配置は一括設定でまとめて渡せる。
    static func TS_IO_01_configuresStyle(toast: any KsToast) {
        toast.style = ToastStyle(
            backgroundColor: .darkGray,
            textColor: .white,
            fontSize: 16,
            cornerRadius: 22,
            defaultDuration: 2000,
            defaultPlacement: DialogPlacement(verticalAlignment: .end, offsetY: -120)
        )
    }

    // MARK: カスタム View の登録

    /// 従来 View 系の factory で登録できる。
    static func TS_IO_01_registersUIKitContent(registry: ToastViewRegistry) {
        registry.register(ConsumerToastViewModel.self) { viewModel in
            let label = UILabel()
            label.text = viewModel.title
            return label
        }
    }

    /// SwiftUI の View を返す factory で登録できる。
    static func TS_IO_01_registersSwiftUIContent(registry: ToastViewRegistry) {
        registry.register(ConsumerToastViewModel.self) { viewModel in
            HStack {
                Image(systemName: "checkmark")
                Text(viewModel.title)
            }
        }
    }

    // MARK: 登録済み表示とインライン表示

    /// 登録済みの ViewModel はインスタンスを渡して表示できる。
    static func TS_IO_01_showsRegisteredViewModel(toast: any KsToast) throws {
        try toast.show(ConsumerToastViewModel(title: "同期しました"))
        try toast.show(ConsumerToastViewModel(title: "同期しました"), duration: 1200)
        try toast.show(
            ConsumerToastViewModel(title: "同期しました"),
            duration: 1200,
            placement: DialogPlacement(verticalAlignment: .start)
        )
    }

    /// 登録せずにその場の factory で表示できる (従来 View 系 / SwiftUI 系)。
    static func TS_IO_01_showsInlineFactory(toast: any KsToast) throws {
        try toast.show(ConsumerToastViewModel(title: "その場")) { viewModel in
            let label = UILabel()
            label.text = viewModel.title
            return label
        }
        try toast.show(ConsumerToastViewModel(title: "その場")) { viewModel in
            Text(viewModel.title)
        }
        try toast.show(
            ConsumerToastViewModel(title: "その場"),
            duration: 1200,
            placement: DialogPlacement(verticalAlignment: .end),
            factory: { viewModel in
                let label = UILabel()
                label.text = viewModel.title
                return label
            }
        )
        try toast.show(
            ConsumerToastViewModel(title: "その場"),
            duration: 1200,
            placement: DialogPlacement(verticalAlignment: .end),
            factory: { viewModel in Text(viewModel.title) }
        )
    }

    // MARK: ViewModel の型を渡す表示

    /// ViewModel factory は View factory と同じ名前で、`viewModel:` のラベルで登録できる。
    static func TS_YI_01_registersViewModelFactory(registry: ToastViewRegistry) {
        registry.register(ConsumerToastViewModel.self) {
            ConsumerToastViewModel(title: "保存しました")
        }
        registry.register(ConsumerToastViewModel.self, viewModel: {
            ConsumerToastViewModel(title: "保存しました")
        })
    }

    /// 型を渡す表示は configure あり / なし・duration あり・置き場所ありで書ける。
    static func TS_YI_01_showsRegisteredViewModelType(toast: any KsToast) throws {
        try toast.show(ConsumerMutableToastViewModel.self)
        try toast.show(ConsumerMutableToastViewModel.self) { viewModel in
            viewModel.title = "同期しました"
        }
        try toast.show(ConsumerMutableToastViewModel.self, duration: 1200)
        try toast.show(ConsumerMutableToastViewModel.self, duration: 1200) { viewModel in
            viewModel.title = "同期しました"
        }
        try toast.show(
            ConsumerMutableToastViewModel.self,
            duration: 1200,
            placement: DialogPlacement(verticalAlignment: .start)
        )
        try toast.show(
            ConsumerMutableToastViewModel.self,
            duration: 1200,
            placement: DialogPlacement(verticalAlignment: .start),
            configure: { viewModel in viewModel.title = "同期しました" }
        )
    }

    // MARK: 既定エントリ

    /// 既定シングルトンと DI 注入のどちらも同じ契約で扱える。
    static func TS_IO_01_usesSharedEntryAndInjectedInstance() {
        let shared: any KsToast = Toast.shared
        let injected: any KsToast = Toast()
        _ = shared
        _ = injected
    }

    // MARK: 負の検証 (fire-and-forget に無い呼び出し面は生えていない)

    #if KSDIALOGS_NEGATIVE_CHECK_TOAST_HIDE
    /// 閉じる手段は契約に無い。消滅の契機は duration の経過だけである。
    /// 期待する診断: value of type 'any KsToast' has no member 'hide'
    static func TS_IO_03_rejectsHideOnToast(toast: any KsToast) {
        toast.hide()
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_TOAST_SHOW_RESULT
    /// show は戻り値を持たず、表示の終了を待つ手段も無い。
    /// 期待する診断: cannot convert value of type '()' to specified type 'String'
    static func TS_IO_03_rejectsReceivingResultFromToastShow(toast: any KsToast) {
        let handle: String = toast.show(message: "保存しました")
        _ = handle
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_TOAST_SHOW_STYLE
    /// 表示 API に style 引数はない。見た目は設定プロパティで一括設定する。
    /// 期待する診断: extra argument 'style' in call
    static func TS_IO_03_rejectsStyleArgumentOnToastShow(toast: any KsToast) {
        toast.show(message: "保存しました", style: ToastStyle())
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_TOAST_OPTIONS
    /// Toast には覆いも外側タップも無いため、器メタ属性の設定プロパティは持たない。
    /// 期待する診断: value of type 'any KsToast' has no member 'options'
    static func TS_IO_03_rejectsOptionsPropertyOnToast(toast: any KsToast) {
        toast.options = DialogOptions()
    }
    #endif
}
#endif
