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

/// 別の仕事として投入した呼び出しが走り出したことを書き留める。
///
/// 仕事を作っただけでは、その中身が走り出したかは呼び出し側から分からない。
/// 呼び出しの直前にここへ印を付けておくと、走り出した時点を待ち側から確かめられる。
///
/// 印が示すのは「その仕事が最初の中断点まで進んだ」ことに限る。印と目的の中断点の間に
/// 実行機の乗り換えが挟まらない経路 — UI スレッド隔離の呼び出しだけを並べた仕事 — に置いたときだけ、
/// 「その中断点で待ちに入った」ことの根拠として使える。
@MainActor
final class LoadingTestCallStartRecorder {
    private(set) var hasStarted = false

    func markStarted() {
        hasStarted = true
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
