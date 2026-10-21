#if canImport(UIKit)
import Testing
import UIKit

/// 器の矩形と、SwiftUI の中身が描かれた矩形を時間を追って測る補助。
///
/// 描かれた矩形は中身に重ねた UIView の目印で読む。中身から読む geometry は描画と食い違う
/// ことがあるため、位置の判定には使わない。
@MainActor
enum SwiftUIPlacementSampling {
    /// 位置と大きさの比較の許容誤差。
    static let tolerance: CGFloat = 0.5

    /// 今から 1 秒間、器の矩形と目印の矩形を測る。既定は 50 ms ごとの 21 回。
    ///
    /// 測るたびにレイアウトパスを 1 回走らせ、そのパスが終わった状態を記録する。間隔を詰めると、
    /// 切り替わりの途中のパスで一瞬だけ違う位置に置かれていないかを見られる。
    static func sample(
        window: UIWindow,
        container: @escaping @MainActor () -> UIView,
        drawn probes: [SwiftUIDrawnFrameProbe],
        interval: Duration = .milliseconds(50),
        count: Int = 21
    ) async -> [SwiftUIPlacementSample] {
        var samples: [SwiftUIPlacementSample] = []
        for index in 0..<count {
            if index > 0 {
                try? await Task.sleep(for: interval)
            }
            window.layoutIfNeeded()
            let containerView = container()
            samples.append(
                SwiftUIPlacementSample(
                    container: containerView.convert(containerView.bounds, to: nil),
                    drawn: probes.map(\.windowFrame)
                )
            )
        }
        return samples
    }

    /// 目印の矩形が条件を満たすまで、レイアウトを進めながら待つ。
    static func waitUntilDrawn(
        window: UIWindow,
        _ probe: SwiftUIDrawnFrameProbe,
        timeout: Duration = .seconds(2),
        _ condition: @MainActor (CGRect) -> Bool
    ) async -> Bool {
        await DialogTestWaiting.waitUntil(timeout: timeout) {
            window.layoutIfNeeded()
            return probe.windowFrame.map(condition) ?? false
        }
    }

    static func isClose(_ lhs: CGRect?, _ rhs: CGRect, tolerance: CGFloat = tolerance) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    /// 全サンプルで、器の矩形が `container` と一致することを確かめる。
    static func expectContainer(
        _ samples: [SwiftUIPlacementSample],
        equals container: CGRect,
        _ note: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            samples.allSatisfy { isClose($0.container, container) },
            "\(note) — 器はずっと \(container) のはずが \(samples.map(\.container))",
            sourceLocation: sourceLocation
        )
    }

    /// 全サンプルで、`index` 番目の目印の矩形が `drawn` と一致することを確かめる。
    static func expectDrawn(
        _ samples: [SwiftUIPlacementSample],
        at index: Int = 0,
        equals drawn: CGRect,
        _ note: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            samples.allSatisfy { isClose($0.drawn[index], drawn) },
            "\(note) — 描かれた位置はずっと \(drawn) のはずが \(samples.map { $0.drawn[index] })",
            sourceLocation: sourceLocation
        )
    }
}
#endif
