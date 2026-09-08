import Testing

@testable import KsDialogs

@Suite("結果はちょうど1回だけ確定する")
struct DialogNotifierTests {
    @Test("確定後の再報告は無効")
    func reportAfterSettlementIsIgnored() {
        let resultChannel = DialogResultChannel()
        let notifier = DialogNotifier<Bool>(resultChannel: resultChannel)
        let recorder = DialogOutcomeRecorder()
        resultChannel.onSettle { recorder.record($0) }

        notifier.complete(true)
        notifier.complete(false)
        notifier.cancel()

        #expect(recorder.count == 1)
        #expect(recorder.firstCompletedValue(as: Bool.self) == true)
        #expect(resultChannel.isResultSettled)
    }

    @Test("受け取り側の登録より先に確定した結果も1回だけ届く")
    func settlementBeforeHandlerRegistrationIsDeliveredOnce() {
        let resultChannel = DialogResultChannel()
        let notifier = DialogNotifier<Bool>(resultChannel: resultChannel)
        let recorder = DialogOutcomeRecorder()

        notifier.cancel()
        notifier.complete(true)
        resultChannel.onSettle { recorder.record($0) }

        #expect(recorder.count == 1)
        #expect(recorder.isFirstCancelled)
    }
}
