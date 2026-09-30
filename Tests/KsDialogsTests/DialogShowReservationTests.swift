#if canImport(UIKit)
import Testing
import UIKit

// 表示の順番の予約は、別モジュールのブリッジ専用の隠れた面にある。
@_spi(KsDialogsBridge) @testable import KsDialogs

/// ブリッジ専用の面 (表示の順番の予約) を確かめる。
///
/// UI スレッドへ移ってから show を呼ぶ呼び出し口は、移る前に予約を取り、移った先で予約つきの
/// show に渡す。移った先の処理が始まる順に関係なく、予約した順に表示を待つ列へ並ぶ。
@Suite("表示の順番の予約", .serialized)
@MainActor
struct DialogShowReservationTests {
    /// 提示先の無い組み立て。作った中身には ViewModel の message を識別子として付ける。
    private static func makeHarnessWithoutHost() -> DialogTestHarness {
        let harness = DialogTestHarness(hasPresentationHost: false)
        harness.registry.register(BasicTestDialogViewModel.self) { viewModel, _ in
            let view = DialogTestContentView()
            view.accessibilityIdentifier = viewModel.message
            return view
        }
        return harness
    }

    @Test("予約した順に列へ並び、show を始めた順が逆でも予約の順に表示される")
    func showsFollowTheReservationOrder() async throws {
        let harness = Self.makeHarnessWithoutHost()
        let queue = harness.presentationSurface.hostWaitQueue
        let viewModelA = BasicTestDialogViewModel(message: "A")
        let viewModelB = BasicTestDialogViewModel(message: "B")

        let reservationA = harness.dialogs.reserveShow()
        let reservationB = harness.dialogs.reserveShow()
        #expect(queue.waitingCount == 2, "予約した時点で順番が数えられる")

        // 予約とは逆の順に show を始める。
        let showB = Task { try await harness.dialogs.show(viewModelB, reservation: reservationB) }
        try #require(await DialogTestWaiting.waitUntil { queue.waitingCount == 2 })
        let showA = Task { try await harness.dialogs.show(viewModelA, reservation: reservationA) }
        try #require(await DialogTestWaiting.waitUntil { viewModelA.notifier != nil && viewModelB.notifier != nil })

        harness.presentationSurface.isPresentationHostAvailable = true
        harness.presentationSurface.fireHostAppearance()

        try #require(await harness.waitForPresentedContainers(count: 2), "2 枚とも表示される")
        #expect(
            harness.presentedContainers.map { $0.contentView.accessibilityIdentifier } == ["A", "B"],
            "予約した A、B の順に表示され、B が手前に重なる"
        )

        try #require(viewModelB.notifier).complete(true)
        #expect(try await showB.value == .completed(true))
        try #require(viewModelA.notifier).complete(false)
        #expect(try await showA.value == .completed(false))
    }

    @Test("予約つきの show が列に着く前に失敗しても、予約は手放されて後ろの show を止めない")
    func failedReservedShowReleasesItsTurn() async throws {
        let harness = Self.makeHarnessWithoutHost()
        harness.presentationSurface.isPresentationHostAvailable = true
        let viewModel = BasicTestDialogViewModel(message: "後ろ")

        let reservation = harness.dialogs.reserveShow()
        let showAfter = Task { try await harness.dialogs.show(viewModel) }
        try #require(await DialogTestWaiting.waitUntil { harness.presentationSurface.hostWaitQueue.waitingCount == 2 })

        // 登録の無い ViewModel で予約つきの show を呼ぶと、列に着く前に失敗する。
        await #expect(throws: DialogError.self) {
            try await harness.dialogs.show(UnregisteredTestDialogViewModel(), reservation: reservation)
        }

        try #require(await harness.waitForPresentedContainers(count: 1), "後ろの show が表示される")
        try #require(viewModel.notifier).complete(true)
        #expect(try await showAfter.value == .completed(true))
    }
}
#endif
