#if canImport(UIKit)
import Testing
import UIKit

@testable import KsDialogs

/// 既定ローディングのスタイル (core/ADR-0023) を確かめる。
///
/// スタイルは設定プロパティへの一括設定だけで供給され、器は各表示の開始時に読む。
/// そのため表示中の設定変更は現在の表示に効かず、次の表示から観察できる。
@Suite("既定ローディングのスタイル", .serialized)
@MainActor
struct LoadingStyleTests {
    @Test("[LD-ST-01] スタイル変更は次の表示から効く")
    func LD_ST_01_styleChangeAppliesFromNextDisplay() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        harness.loading.style = LoadingStyle(
            indicatorColor: .white,
            messageFontSize: 14,
            messageColor: .white,
            defaultMessage: "読み込み中"
        )

        await harness.loading.show()
        let presentedContentView = try #require(harness.coordinator.presentedBuiltinContentView)

        harness.loading.style = LoadingStyle(
            indicatorColor: .red,
            messageFontSize: 24,
            messageColor: .yellow,
            defaultMessage: "処理中"
        )

        #expect(presentedContentView.displayedText == "読み込み中", "表示中の見た目は変わらない")
        #expect(presentedContentView.displayedMessageFont.pointSize == 14)
        #expect(presentedContentView.displayedMessageColor == .white)
        #expect(presentedContentView.displayedIndicatorColor == .white)

        await harness.loading.hide()
        await harness.loading.show()
        let restyledContentView = try #require(harness.coordinator.presentedBuiltinContentView)

        #expect(restyledContentView.displayedText == "処理中", "再表示から変更後のスタイルが効く")
        #expect(restyledContentView.displayedMessageFont.pointSize == 24)
        #expect(restyledContentView.displayedMessageColor == .yellow)
        #expect(restyledContentView.displayedIndicatorColor == .red)

        await harness.loading.hide()
    }

    @Test("[LD-ST-02] メッセージ未指定なら既定メッセージが表示される")
    func LD_ST_02_defaultMessageIsUsedWhenMessageIsOmitted() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        harness.loading.style = LoadingStyle(defaultMessage: "読み込み中")

        await harness.loading.show()
        #expect(harness.builtinText == "読み込み中")
        await harness.loading.hide()

        await harness.loading.show(message: "保存しています")
        #expect(harness.builtinText == "保存しています", "指定したメッセージが既定メッセージより優先される")
        await harness.loading.hide()
    }

    @Test("[LD-ST-03] フォーマット関数の差し替えが進捗表示に反映される")
    func LD_ST_03_customProgressFormatDrivesDisplayedText() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }
        harness.loading.style = LoadingStyle(
            defaultMessage: "読み込み中",
            progressFormat: { message, progress in
                guard let progress else { return "[\(message ?? "")]" }
                return "[\(message ?? "")|\(Int((progress * 100).rounded()))]"
            }
        )
        let gate = DialogTransitionGate()
        let reporter = LoadingTestProgressReporter()

        let scope = Task {
            try await harness.loading.start { report in
                await MainActor.run { reporter.capture(report) }
                try await gate.wait()
            }
        }
        try #require(await harness.waitUntilPresenting())
        // 報告口は処理が走り始めてから届く。表示の成立だけを待って報告すると、
        // 報告口を掴む前の報告になって取りこぼす。
        try #require(await DialogTestWaiting.waitUntil { reporter.isCaptured })

        #expect(harness.builtinText == "[読み込み中]", "進捗未報告でも差し替えた関数が使われる")

        reporter.report(0.45)
        try #require(await DialogTestWaiting.waitUntil { harness.builtinText == "[読み込み中|45]" })

        gate.open()
        try await scope.value
    }

    @Test("内蔵コンテンツのメッセージは太字で、行間が空く")
    func builtinMessageIsBoldWithLineSpacing() async throws {
        let harness = LoadingTestHarness()
        defer { harness.tearDown() }

        await harness.loading.show(message: "読み込み中")
        let contentView = try #require(harness.coordinator.presentedBuiltinContentView)

        #expect(contentView.displayedMessageFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(contentView.displayedMessageLineSpacing > 0, "複数行になったときに行が詰まらない")

        await harness.loading.hide()
    }

    @Test("既定のフォーマットはメッセージと百分率を改行で連ねる")
    func defaultProgressFormatJoinsMessageAndPercentage() async throws {
        let format = LoadingStyle.defaultProgressFormat

        #expect(format("読み込み中", nil) == "読み込み中")
        #expect(format("読み込み中", 0.45) == "読み込み中\n45%")
        #expect(format(nil, 0.45) == "45%")
        #expect(format(nil, nil) == "")
    }
}
#endif
