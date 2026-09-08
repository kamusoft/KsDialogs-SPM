#if canImport(UIKit)
import Foundation

@testable import KsDialogs

/// カスタム Loading の表示に使う素の ViewModel。進捗の受け口は持たない。
final class LoadingTestViewModel: LoadingViewModel {
    init() {}
}

/// 進捗の受け口を実装した ViewModel。転送された値を順に書き留める。
@MainActor
final class ProgressReceivingLoadingTestViewModel: LoadingViewModel, LoadingProgressReceiver {
    private(set) var receivedProgress: [Double] = []

    nonisolated init() {}

    func onProgress(_ progress: Double) {
        receivedProgress.append(progress)
    }
}

/// configure から状態を設定でき、進捗の受け口も持つ ViewModel。型指定の表示の観察に使う。
/// 状態の変更は UI スレッドに限るため MainActor に閉じる。
@MainActor
final class ConfigurableLoadingTestViewModel: LoadingViewModel, LoadingProgressReceiver {
    /// 中身の生成時に読まれる表題。configure で設定する。
    var title: String

    /// 転送された進捗を受理順に書き留めたもの。
    private(set) var receivedProgress: [Double] = []

    nonisolated init(title: String = "factory の既定") {
        self.title = title
    }

    func onProgress(_ progress: Double) {
        receivedProgress.append(progress)
    }
}

/// Loading レジストリに登録しない ViewModel。構成ミスの再現に使う。
final class UnregisteredLoadingTestViewModel: LoadingViewModel {
    init() {}
}

/// Dialog と Loading の両方の契約に準拠する ViewModel。
/// 同じ型を両レジストリへ別々の View で登録し、互いに影響しないことを見るのに使う。
final class DualRegistryLoadingTestViewModel: LoadingViewModel, DialogViewModel {
    typealias Result = Bool

    init() {}
}
#endif
