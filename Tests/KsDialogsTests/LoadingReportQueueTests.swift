#if canImport(UIKit)
import Foundation
import Testing

@testable import KsDialogs

/// 進捗報告と終了の受理順を守る待ち行列を確かめる。
///
/// Loading の契約は「報告口は任意スレッドから呼べ、受理は UI スレッド上で呼ばれた順に直列化される」
/// (core/ADR-0024)。受理を独立した仕事として個別に投げると、この順序も、報告と終了処理の
/// 前後関係も保証されない。ここではその保証を機構の側で固定する。
@Suite("Loading の受理の直列化")
struct LoadingReportQueueTests {
    @Test("積んだ順に受理される")
    func acceptsInEnqueuedOrder() async {
        let queue = LoadingReportQueue()
        let recorder = LoadingTestProgressRecorder()

        for step in 1...50 {
            queue.enqueue { recorder.record(Double(step)) }
        }
        await queue.drain()

        #expect(recorder.values == (1...50).map(Double.init))
    }

    @Test("受理が待ちを含んでいても順序が保たれる")
    func keepsOrderAcrossSuspensions() async {
        let queue = LoadingReportQueue()
        let recorder = LoadingTestProgressRecorder()

        // 先に積んだ受理ほど長く待つ形にして、追い越しが起きれば順序が崩れるようにする。
        for step in 1...5 {
            queue.enqueue {
                try? await Task.sleep(for: .milliseconds(20 - step * 3))
                recorder.record(Double(step))
            }
        }
        await queue.drain()

        #expect(recorder.values == (1...5).map(Double.init))
    }

    @Test("drain は積んだ受理をすべて待ってから戻る")
    func drainWaitsForEveryEnqueuedWork() async {
        let queue = LoadingReportQueue()
        let recorder = LoadingTestProgressRecorder()

        queue.enqueue {
            try? await Task.sleep(for: .milliseconds(30))
            recorder.record(1)
        }
        queue.enqueue { recorder.record(2) }

        await queue.drain()

        #expect(recorder.values == [1, 2], "戻った時点で発行済みの受理は残っていない")
    }

    @Test("任意のスレッドから積める")
    func acceptsEnqueuesFromAnyThread() async {
        let queue = LoadingReportQueue()
        let recorder = LoadingTestProgressRecorder()

        await withTaskGroup(of: Void.self) { group in
            for step in 1...20 {
                group.addTask {
                    queue.enqueue { recorder.record(Double(step)) }
                }
            }
        }
        await queue.drain()

        #expect(recorder.values.count == 20, "積んだ受理はどのスレッドから来ても取りこぼされない")
        #expect(Set(recorder.values) == Set((1...20).map(Double.init)))
    }
}
#endif
