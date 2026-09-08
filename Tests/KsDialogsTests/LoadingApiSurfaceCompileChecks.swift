#if canImport(UIKit)
import SwiftUI
import UIKit

// 利用者と同じ側から見た公開面だけで書く検証なので、内部シンボルが見える @testable import は使わない。
// 公開すべき型が誤って internal になっていれば、このファイルのビルドが失敗する。
import KsDialogs

/// カスタム Loading の表示に使う、利用者が書くのと同じ形の ViewModel。
final class ConsumerLoadingViewModel: LoadingViewModel {
    let title: String

    init(title: String) {
        self.title = title
    }
}

/// 進捗の受け口を実装した、利用者が書くのと同じ形の ViewModel。
@MainActor
final class ConsumerProgressLoadingViewModel: LoadingViewModel, LoadingProgressReceiver {
    private(set) var progress: Double = 0

    nonisolated init() {}

    func onProgress(_ progress: Double) {
        self.progress = progress
    }
}

/// Loading の公開 API 形状のコンパイル検証。
///
/// 命令形・スコープ形の呼び出し面、配置引数、スタイルの一括設定、UIKit / SwiftUI 両系統の登録、
/// インライン factory 表示、進捗受け口の準拠が、**型注釈を足さずに書けること**を
/// 既定のビルドの中で確かめる。検証はコンパイルが通ること自体であり、
/// 実行時の挙動は別のテストが受け持つ。
///
/// 負の検証 (見た目と器メタ属性は設定プロパティ専用で、表示 API の引数では渡せない) は
/// 禁止形状ごとに別のフラグへ分けてあり、**フラグを1つだけ定義したビルドが失敗すること**が
/// 期待結果になる:
///
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_LOADING_SHOW_STYLE'
///     xcodebuild build-for-testing -scheme KsDialogs \
///       -destination 'platform=iOS Simulator,name=<機種名>' \
///       OTHER_SWIFT_FLAGS='$(inherited) -DKSDIALOGS_NEGATIVE_CHECK_LOADING_SHOW_OPTIONS'
@MainActor
enum LoadingApiSurfaceCompileChecks {
    // MARK: 命令形とスコープ形

    /// 命令形の表示・メッセージ更新・閉鎖が書ける。
    static func LD_IO_01_showsSetsMessageAndHides(loading: any KsLoading) async {
        await loading.show()
        await loading.show(message: "読み込み中")
        await loading.show(message: "読み込み中", placement: DialogPlacement(verticalAlignment: .end))
        await loading.setMessage("あと少し")
        await loading.hide()
    }

    /// スコープ形は処理の戻り値をそのまま返し、処理は進捗の報告口を受け取る。
    static func LD_IO_01_startsScopeWithProgressAndReturnsValue(loading: any KsLoading) async throws {
        let count: Int = try await loading.start(message: "集計中") { report in
            report(0.5)
            return 42
        }
        _ = count

        let text: String = try await loading.start(
            message: "集計中",
            placement: DialogPlacement(horizontalAlignment: .start)
        ) { report in
            report(1)
            return "完了"
        }
        _ = text
    }

    // MARK: スタイルと器メタ属性の設定プロパティ

    /// スタイルはフォーマット関数を含めて一括で設定でき、器メタ属性は既存の型で設定できる。
    static func LD_IO_01_configuresStyleAndOptions(loading: any KsLoading) {
        loading.style = LoadingStyle(
            indicatorColor: .white,
            messageFontSize: 16,
            messageColor: .white,
            defaultMessage: "読み込み中",
            progressFormat: { message, progress in
                guard let progress else { return message ?? "" }
                return "\(message ?? "") \(Int(progress * 100))%"
            }
        )
        loading.options = DialogOptions(overlayColor: .black.withAlphaComponent(0.5))
    }

    // MARK: カスタム View の登録

    /// 従来 View 系の factory で登録できる。
    static func LD_IO_01_registersUIKitContent(registry: LoadingViewRegistry) {
        registry.register(ConsumerLoadingViewModel.self) { viewModel in
            let label = UILabel()
            label.text = viewModel.title
            return label
        }
    }

    /// SwiftUI の View を返す factory で登録できる。
    static func LD_IO_01_registersSwiftUIContent(registry: LoadingViewRegistry) {
        registry.register(ConsumerProgressLoadingViewModel.self) { viewModel in
            VStack {
                ProgressView(value: viewModel.progress)
                Text("読み込み中")
            }
        }
    }

    // MARK: 登録済み表示とインライン表示

    /// 登録済みの ViewModel はインスタンスを渡して表示・スコープ形で実行できる。
    static func LD_IO_01_showsAndStartsRegisteredViewModel(loading: any KsLoading) async throws {
        try await loading.show(ConsumerLoadingViewModel(title: "同期中"))
        try await loading.show(
            ConsumerLoadingViewModel(title: "同期中"),
            placement: DialogPlacement(verticalAlignment: .start)
        )
        let value: Int = try await loading.start(ConsumerLoadingViewModel(title: "同期中")) { report in
            report(0.25)
            return 1
        }
        _ = value
    }

    /// 登録せずにその場の factory で表示・スコープ形の実行ができる (従来 View 系 / SwiftUI 系)。
    static func LD_IO_01_showsAndStartsInlineFactory(loading: any KsLoading) async throws {
        try await loading.show(ConsumerLoadingViewModel(title: "その場")) { viewModel in
            let label = UILabel()
            label.text = viewModel.title
            return label
        }
        try await loading.show(ConsumerProgressLoadingViewModel()) { viewModel in
            ProgressView(value: viewModel.progress)
        }
        let value: Bool = try await loading.start(
            ConsumerLoadingViewModel(title: "その場"),
            placement: DialogPlacement(verticalAlignment: .end),
            factory: { viewModel in
                let label = UILabel()
                label.text = viewModel.title
                return label
            }
        ) { report in
            report(0.75)
            return true
        }
        _ = value
        let progressValue: Double = try await loading.start(
            ConsumerProgressLoadingViewModel(),
            factory: { viewModel in ProgressView(value: viewModel.progress) }
        ) { report in
            report(0.5)
            return 0.5
        }
        _ = progressValue
    }

    // MARK: ViewModel の型を渡す表示

    /// ViewModel factory は View factory と同じ名前で、`viewModel:` のラベルで登録できる。
    static func LD_YI_01_registersViewModelFactory(registry: LoadingViewRegistry) {
        registry.register(ConsumerLoadingViewModel.self) {
            ConsumerLoadingViewModel(title: "読み込み中")
        }
        registry.register(ConsumerLoadingViewModel.self, viewModel: {
            ConsumerLoadingViewModel(title: "読み込み中")
        })
    }

    /// 型を渡す表示は configure あり / なし・非同期 configure・置き場所ありで書ける。
    static func LD_YI_01_showsRegisteredViewModelType(loading: any KsLoading) async throws {
        try await loading.show(ConsumerLoadingViewModel.self)
        try await loading.show(ConsumerProgressLoadingViewModel.self) { viewModel in
            viewModel.onProgress(0)
        }
        try await loading.show(ConsumerProgressLoadingViewModel.self) { viewModel in
            try await Task.sleep(for: .milliseconds(1))
            viewModel.onProgress(0.5)
        }
        try await loading.show(
            ConsumerLoadingViewModel.self,
            placement: DialogPlacement(verticalAlignment: .start)
        )
        try await loading.show(
            ConsumerProgressLoadingViewModel.self,
            placement: DialogPlacement(verticalAlignment: .start),
            configure: { viewModel in viewModel.onProgress(0.25) }
        )
    }

    /// 型を渡すスコープ形も同じ省略形で書け、処理の戻り値をそのまま返す。
    static func LD_YI_01_startsRegisteredViewModelType(loading: any KsLoading) async throws {
        let count: Int = try await loading.start(ConsumerLoadingViewModel.self) { report in
            report(0.5)
            return 42
        }
        _ = count

        let text: String = try await loading.start(
            ConsumerProgressLoadingViewModel.self,
            configure: { viewModel in viewModel.onProgress(0) }
        ) { report in
            report(1)
            return "完了"
        }
        _ = text

        try await loading.start(
            ConsumerLoadingViewModel.self,
            placement: DialogPlacement(verticalAlignment: .end)
        ) { report in
            report(0.75)
        }
        try await loading.start(
            ConsumerProgressLoadingViewModel.self,
            placement: DialogPlacement(verticalAlignment: .end),
            configure: { viewModel in viewModel.onProgress(0.1) }
        ) { report in
            report(0.75)
        }
    }

    // MARK: 既定エントリ

    /// 既定シングルトンと DI 注入のどちらも同じ契約で扱える。
    static func LD_IO_01_usesSharedEntryAndInjectedInstance() {
        let shared: any KsLoading = Loading.shared
        let injected: any KsLoading = Loading()
        _ = shared
        _ = injected
    }

    // MARK: 負の検証 (表示 API に見た目・器メタ属性の引数はない)

    #if KSDIALOGS_NEGATIVE_CHECK_LOADING_SHOW_STYLE
    /// 表示 API に style 引数はない。見た目は設定プロパティで一括設定する。
    /// 期待する診断: extra argument 'style' in call
    static func rejectsStyleArgumentOnLoadingShow(loading: any KsLoading) async {
        await loading.show(message: "読み込み中", style: LoadingStyle())
    }
    #endif

    #if KSDIALOGS_NEGATIVE_CHECK_LOADING_SHOW_OPTIONS
    /// 表示 API に options 引数はない。既定ローディングの器メタ属性は設定プロパティで渡す。
    /// 期待する診断: extra argument 'options' in call
    static func rejectsOptionsArgumentOnLoadingShow(loading: any KsLoading) async {
        await loading.show(message: "読み込み中", options: DialogOptions())
    }
    #endif
}
#endif
