#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// スコープ形の失敗を再現するための誤り。
enum LoadingTestScopeError: Error {
    case failed
}

/// スコープ形の処理が完了したことを書き留める。
@MainActor
final class LoadingTestActionRecorder {
    private(set) var completionCount = 0

    func recordCompletion() {
        completionCount += 1
    }
}

/// スコープ形が受け取った進捗の報告口を、処理の外から使えるように取り置く。
@MainActor
final class LoadingTestProgressReporter {
    private var capturedReport: (@Sendable (Double) -> Void)?

    var isCaptured: Bool {
        capturedReport != nil
    }

    func capture(_ report: @escaping @Sendable (Double) -> Void) {
        capturedReport = report
    }

    func report(_ progress: Double) {
        capturedReport?(progress)
    }
}

/// factory が生成した View を書き留める。
/// 生成のたびに増えるので、使い捨て生成の回数も観察できる。
@MainActor
final class LoadingTestViewRecorder {
    private(set) var views: [UIView] = []

    var lastView: UIView? {
        views.last
    }

    func record(_ view: UIView) {
        views.append(view)
    }
}

/// 型指定の表示の各段階を書き留める。
///
/// ViewModel factory が作った ViewModel と、View factory が中身を作るときに読んだ表題を
/// それぞれ生成順に持つので、どちらの factory が何回呼ばれたかも観察できる。
@MainActor
final class LoadingTypedShowRecorder {
    private(set) var createdViewModels: [ConfigurableLoadingTestViewModel] = []
    private(set) var observedTitles: [String] = []

    /// View factory が中身を作った回数。
    var creationCount: Int {
        observedTitles.count
    }

    func recordCreation(_ viewModel: ConfigurableLoadingTestViewModel) {
        createdViewModels.append(viewModel)
    }

    func recordContent(title: String) {
        observedTitles.append(title)
    }
}

/// 処理の走行中に器の状態を書き留める。
@MainActor
final class LoadingTestContainerObserver {
    private(set) var containerViewDuringAction: UIView?

    func captureContainerView(of harness: LoadingTestHarness) {
        containerViewDuringAction = harness.containerView
    }
}
#endif
