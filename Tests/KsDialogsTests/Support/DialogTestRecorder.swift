#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// View factory の呼び出しと show の完了を記録する。
@MainActor
final class DialogTestRecorder<Value: Sendable> {
    private(set) var createdViews: [UIView] = []
    private(set) var notifiers: [DialogNotifier<Value>] = []
    private(set) var results: [DialogResult<Value>] = []

    /// factory が生成した View と、その回の結果報告口を記録する。
    func record(view: UIView, notifier: DialogNotifier<Value>) {
        createdViews.append(view)
        notifiers.append(notifier)
    }

    /// 結果報告口だけを記録する。View のインスタンスを手に持たない SwiftUI の factory 向け。
    func record(notifier: DialogNotifier<Value>) {
        notifiers.append(notifier)
    }

    /// 結果報告口を記録して中身をそのまま返す。
    /// SwiftUI の factory は中身を組み立てる式しか書けないため、記録を式の中に畳み込む。
    func recording<Content: View>(notifier: DialogNotifier<Value>, content: Content) -> Content {
        notifiers.append(notifier)
        return content
    }

    /// show が返した結果を記録する。
    func record(result: DialogResult<Value>) {
        results.append(result)
    }

    /// index 番目の View が生成されるまで待ち、その回の結果報告口を返す。
    func notifier(at index: Int) async throws -> DialogNotifier<Value> {
        let appeared = await DialogTestWaiting.waitUntil { self.notifiers.count > index }
        try #require(appeared, "index \(index) の View factory が呼ばれなかった")
        return notifiers[index]
    }
}
#endif
