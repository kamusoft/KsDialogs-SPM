#if canImport(UIKit)
import Foundation

/// 表示に使う中身の指定。
enum ToastContentRequest: Sendable {
    /// ライブラリ同梱のデフォルト View。メッセージだけを運ぶ。
    case builtin(message: String)
    /// レジストリに登録済みの ViewModel から作るカスタム Toast View。
    case registered(viewModel: any ToastViewModel)
    /// レジストリを経由せず、その場で渡された factory から作るカスタム Toast View (core/ADR-0013)。
    case inline(viewModel: any ToastViewModel, factory: ToastViewFactory)
    /// 呼び出し時点でレジストリから解決済みの factory と、UI スレッド上で作る ViewModel から作る
    /// カスタム Toast View (型指定 show。core/ADR-0035)。
    ///
    /// `prepare` は ViewModel の生成と configure をまとめて行い、受理の待ち行列が処理する時点で
    /// UI スレッド上で呼ばれる。その失敗は受理後の失敗 (この表示1枚だけの破棄) になる。
    case typed(prepare: @MainActor @Sendable () throws -> any ToastViewModel, factory: ToastViewFactory)
}
#endif
