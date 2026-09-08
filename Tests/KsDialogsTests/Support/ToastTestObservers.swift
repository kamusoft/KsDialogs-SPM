#if canImport(UIKit)
import UIKit

@testable import KsDialogs

/// 型指定の表示の各段階を書き留める。
///
/// ViewModel factory が作った ViewModel と、View factory が中身を作るときに読んだ表題を
/// それぞれ生成順に持つので、どちらの factory が何回呼ばれたかも観察できる。
@MainActor
final class ToastTypedShowRecorder {
    private(set) var createdViewModels: [ConfigurableToastTestViewModel] = []
    private(set) var observedTitles: [String] = []

    /// View factory が中身を作った回数。
    var creationCount: Int {
        observedTitles.count
    }

    func recordCreation(_ viewModel: ConfigurableToastTestViewModel) {
        createdViewModels.append(viewModel)
    }

    func recordContent(title: String) {
        observedTitles.append(title)
    }
}
#endif
