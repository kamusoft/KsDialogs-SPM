#if canImport(UIKit)
import Foundation
import UIKit

@testable import KsDialogs

/// 出入りの演出のフックが、いつ・どんな引数で呼ばれたかを記録する観測用の道具。
///
/// 記録つきのフックをここから作り、それを `DialogTransition` に載せて中身へ添付する。
@MainActor
final class DialogTransitionProbe {
    /// フックの種類。
    enum Phase: Equatable {
        case presentation
        case dismissal
    }

    /// 観測できた出来事。並びがそのまま時間順になる。
    enum Event: Equatable {
        case started(Phase)
        case finished(Phase)
        case cancelled(Phase)
        case failed(Phase)
    }

    /// フックが呼ばれた1回分の様子。
    struct Call {
        let hostView: UIView
        let isOnMainThread: Bool
        let isOnWindow: Bool
        let size: CGSize
    }

    private(set) var events: [Event] = []
    private(set) var calls: [Phase: [Call]] = [:]

    /// その種類のフックが呼ばれた回数。
    func callCount(_ phase: Phase) -> Int {
        calls[phase]?.count ?? 0
    }

    /// その種類のフックが最初に呼ばれたときの様子。
    func firstCall(_ phase: Phase) -> Call? {
        calls[phase]?.first
    }

    /// その出来事が記録されているか。
    func hasEvent(_ event: Event) -> Bool {
        events.contains(event)
    }

    /// 記録だけして即座に完了するフック。
    func immediateHook(_ phase: Phase) -> DialogTransition.Hook {
        { [self] hostView in
            record(phase, hostView: hostView)
            events.append(.finished(phase))
        }
    }

    /// 記録したあと、門が開くまで完了しないフック。
    /// 門を開けないまま使えば「完了しないフック」の再現になる。
    func gatedHook(_ phase: Phase, gate: DialogTransitionGate) -> DialogTransition.Hook {
        { [self] hostView in
            record(phase, hostView: hostView)
            do {
                try await gate.wait()
                events.append(.finished(phase))
            } catch {
                events.append(.cancelled(phase))
                throw error
            }
        }
    }

    /// 記録したあと失敗するフック。
    func failingHook(_ phase: Phase) -> DialogTransition.Hook {
        { [self] hostView in
            record(phase, hostView: hostView)
            events.append(.failed(phase))
            throw DialogTransitionProbeError.hookFailed
        }
    }

    private func record(_ phase: Phase, hostView: UIView) {
        events.append(.started(phase))
        calls[phase, default: []].append(
            Call(
                hostView: hostView,
                isOnMainThread: Thread.isMainThread,
                isOnWindow: hostView.window != nil,
                size: hostView.bounds.size
            )
        )
    }
}

/// フックの失敗を再現するための誤り。
enum DialogTransitionProbeError: Error {
    case hookFailed
}
#endif
