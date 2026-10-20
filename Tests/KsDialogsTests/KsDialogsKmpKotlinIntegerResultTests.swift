#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

@testable import KsDialogs

/// Kotlin の整数型と対応しない Swift の `Int` / `UInt` を、KMP 面の結果型に指定したときの扱い。
///
/// `Int` / `UInt` を直接書いた呼び出しは非推奨の入口に解決されるため、このファイルのビルドでは
/// 非推奨の警告が出る (警告が出ること自体が確かめたい挙動の一部)。
@Suite("KMP 面の Kotlin の整数型と対応しない結果型", .serialized)
@MainActor
struct KsDialogsKmpKotlinIntegerResultTests {
    private static let intMismatch = KsDialogsKmpError.resultTypeMismatch(expected: "Int32 or Int64", actual: "Int")
    private static let uintMismatch = KsDialogsKmpError.resultTypeMismatch(expected: "UInt32 or UInt64", actual: "UInt")

    /// 共有 VM の型に今登録されている factory の結果型。
    private func registeredResultType(in harness: DialogTestHarness) -> DialogDeclaredResultType? {
        harness.registry
            .factory(forKey: DialogViewModelKey(SharedTestDialogViewModel.self))?
            .declaredResultType
    }

    /// 次の登録が実際に置き換えたことを見分けられるよう、共有 VM の型を別の結果型で登録し直す。
    private func resetRegistration(_ harness: DialogTestHarness) {
        harness.dialogs.kmp.register(SharedTestDialogViewModel.self, result: String.self) { _, _ in
            DialogTestContentView()
        }
        #expect(registeredResultType(in: harness) == DialogDeclaredResultType(String.self))
    }

    // MARK: 非推奨の入口 (IR-KM-01・02)

    @Test("[IR-KM-01] Int を指定した register 4 種は登録し、show と notifier(for:result:) は型付きの失敗になる")
    func intOverloadsRegisterAndFailOnShow() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let intType = DialogDeclaredResultType(Int.self)

        kmp.register(SharedTestDialogViewModel.self, result: Int.self) { _, _ in
            DialogTestContentView()
        }
        #expect(registeredResultType(in: harness) == intType, "結果報告口つきの従来 View 系で登録されること")
        // 結果型を省略した show (= 真偽値の指定) の失敗は、登録の結果型に由来する。
        await #expect(throws: Self.intMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "登録の確認"))
        }

        resetRegistration(harness)
        kmp.register(SharedTestDialogViewModel.self, result: Int.self) { _, _ in
            Text("SwiftUI")
        }
        #expect(registeredResultType(in: harness) == intType, "結果報告口つきの SwiftUI で登録されること")
        await #expect(throws: Self.intMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "登録の確認"))
        }

        resetRegistration(harness)
        kmp.register(SharedTestDialogViewModel.self, result: Int.self) { _ in
            DialogTestContentView()
        }
        #expect(registeredResultType(in: harness) == intType, "ViewModel だけを受け取る従来 View 系で登録されること")
        await #expect(throws: Self.intMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "登録の確認"))
        }

        resetRegistration(harness)
        kmp.register(SharedTestDialogViewModel.self, result: Int.self) { _ in
            Text("SwiftUI")
        }
        #expect(registeredResultType(in: harness) == intType, "ViewModel だけを受け取る SwiftUI で登録されること")
        await #expect(throws: Self.intMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "登録の確認"))
        }

        let viewModel = SharedTestDialogViewModel(message: "確認")
        await #expect(throws: Self.intMismatch) {
            _ = try await kmp.show(viewModel, result: Int.self)
        }
        #expect(throws: Self.intMismatch) {
            _ = try kmp.notifier(for: viewModel, result: Int.self)
        }
        #expect(harness.presentedContainers.isEmpty)
    }

    @Test("[IR-KM-02] UInt を指定した register 4 種は登録し、show と notifier(for:result:) は型付きの失敗になる")
    func uintOverloadsRegisterAndFailOnShow() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let uintType = DialogDeclaredResultType(UInt.self)

        kmp.register(SharedTestDialogViewModel.self, result: UInt.self) { _, _ in
            DialogTestContentView()
        }
        #expect(registeredResultType(in: harness) == uintType, "結果報告口つきの従来 View 系で登録されること")
        // 結果型を省略した show (= 真偽値の指定) の失敗は、登録の結果型に由来する。
        await #expect(throws: Self.uintMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "登録の確認"))
        }

        resetRegistration(harness)
        kmp.register(SharedTestDialogViewModel.self, result: UInt.self) { _, _ in
            Text("SwiftUI")
        }
        #expect(registeredResultType(in: harness) == uintType, "結果報告口つきの SwiftUI で登録されること")
        await #expect(throws: Self.uintMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "登録の確認"))
        }

        resetRegistration(harness)
        kmp.register(SharedTestDialogViewModel.self, result: UInt.self) { _ in
            DialogTestContentView()
        }
        #expect(registeredResultType(in: harness) == uintType, "ViewModel だけを受け取る従来 View 系で登録されること")
        await #expect(throws: Self.uintMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "登録の確認"))
        }

        resetRegistration(harness)
        kmp.register(SharedTestDialogViewModel.self, result: UInt.self) { _ in
            Text("SwiftUI")
        }
        #expect(registeredResultType(in: harness) == uintType, "ViewModel だけを受け取る SwiftUI で登録されること")
        await #expect(throws: Self.uintMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "登録の確認"))
        }

        let viewModel = SharedTestDialogViewModel(message: "確認")
        await #expect(throws: Self.uintMismatch) {
            _ = try await kmp.show(viewModel, result: UInt.self)
        }
        #expect(throws: Self.uintMismatch) {
            _ = try kmp.notifier(for: viewModel, result: UInt.self)
        }
        #expect(harness.presentedContainers.isEmpty)
    }

    // MARK: show の失敗 (IR-KM-03・04)

    @Test("[IR-KM-03] show に Int / UInt を指定すると表示せずに失敗する")
    func showWithIntegerResultTypeFailsWithoutPresenting() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let factoryCalls = DialogTestCallCounter()

        kmp.register(SharedTestDialogViewModel.self, result: Int64.self) { _, _ in
            factoryCalls.increment()
            return DialogTestContentView()
        }
        await #expect(throws: Self.intMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "Int64 の登録"), result: Int.self)
        }
        await #expect(throws: Self.uintMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "Int64 の登録"), result: UInt.self)
        }

        kmp.register(SharedTestDialogViewModel.self) { _, _ in
            factoryCalls.increment()
            return DialogTestContentView()
        }
        await #expect(throws: Self.intMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "真偽値の登録"), result: Int.self)
        }
        await #expect(throws: Self.uintMismatch) {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "真偽値の登録"), result: UInt.self)
        }

        #expect(factoryCalls.count == 0, "View factory が呼ばれないこと")
        #expect(harness.presentedContainers.isEmpty, "ダイアログが表示されないこと")
    }

    @Test("[IR-KM-04] Int / UInt で登録した共有 VM の show は、指定した結果型によらず表示せずに失敗する")
    func showOfIntegerRegisteredViewModelFailsWithoutPresenting() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let factoryCalls = DialogTestCallCounter()

        kmp.register(SharedTestDialogViewModel.self, result: Int.self) { _, _ in
            factoryCalls.increment()
            return DialogTestContentView()
        }
        await #expect(throws: Self.intMismatch, "結果型を省略した show") {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "Int の登録"))
        }
        await #expect(throws: Self.intMismatch, "別の結果型を指定した show") {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "Int の登録"), result: Int64.self)
        }
        await #expect(throws: Self.uintMismatch, "指定した結果型が先に判定されること") {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "Int の登録"), result: UInt.self)
        }

        kmp.register(SharedTestDialogViewModel.self, result: UInt.self) { _, _ in
            factoryCalls.increment()
            return DialogTestContentView()
        }
        await #expect(throws: Self.uintMismatch, "結果型を省略した show") {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "UInt の登録"))
        }
        await #expect(throws: Self.uintMismatch, "別の結果型を指定した show") {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "UInt の登録"), result: Int64.self)
        }
        await #expect(throws: Self.intMismatch, "指定した結果型が先に判定されること") {
            _ = try await kmp.show(SharedTestDialogViewModel(message: "UInt の登録"), result: Int.self)
        }

        #expect(factoryCalls.count == 0, "View factory が呼ばれないこと")
        #expect(harness.presentedContainers.isEmpty, "ダイアログが表示されないこと")
    }

    // MARK: ジェネリックなラッパー越しの指定 (IR-KM-05)

    /// 結果型を型引数で受け取り、そのまま show へ渡す利用者側の関数を模す。
    /// 型引数の中では非推奨の入口が選ばれないため、公開のジェネリックな入口を通る。
    private func showThroughGenericWrapper<Result: Sendable>(
        _ kmp: KsDialogsKmp,
        _ viewModel: SharedTestDialogViewModel,
        result: Result.Type
    ) async throws -> DialogResult<Result> {
        try await kmp.show(viewModel, result: result)
    }

    /// 結果型を型引数で受け取り、そのまま `notifier(for:result:)` へ渡す利用者側の関数を模す。
    private func notifierThroughGenericWrapper<Result: Sendable>(
        _ kmp: KsDialogsKmp,
        _ viewModel: SharedTestDialogViewModel,
        result: Result.Type
    ) throws -> DialogNotifier<Result>? {
        try kmp.notifier(for: viewModel, result: result)
    }

    @Test("[IR-KM-05] ジェネリックなラッパー越しの Int / UInt の指定も同じに失敗する")
    func genericWrapperCallsFailTheSameWay() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let factoryCalls = DialogTestCallCounter()
        kmp.register(SharedTestDialogViewModel.self, result: Int64.self) { _, _ in
            factoryCalls.increment()
            return DialogTestContentView()
        }
        let viewModel = SharedTestDialogViewModel(message: "ラッパー越し")

        await #expect(throws: Self.intMismatch) {
            _ = try await showThroughGenericWrapper(kmp, viewModel, result: Int.self)
        }
        await #expect(throws: Self.uintMismatch) {
            _ = try await showThroughGenericWrapper(kmp, viewModel, result: UInt.self)
        }
        #expect(throws: Self.intMismatch) {
            _ = try notifierThroughGenericWrapper(kmp, viewModel, result: Int.self)
        }
        #expect(throws: Self.uintMismatch) {
            _ = try notifierThroughGenericWrapper(kmp, viewModel, result: UInt.self)
        }

        #expect(factoryCalls.count == 0, "View factory が呼ばれないこと")
        #expect(harness.presentedContainers.isEmpty, "ダイアログが表示されないこと")
    }

    // MARK: 報告口の取り出し (IR-KM-06)

    @Test("[IR-KM-06] notifier(for:result:) に Int / UInt を指定すると、表示中でも登録の型によらず失敗する")
    func notifierWithIntegerResultTypeFailsEvenWhileShowing() async throws {
        let harness = DialogTestHarness()
        let kmp = harness.dialogs.kmp
        let recorder = KmpModelBindingTestRecorder<String>()
        kmp.register(SharedTestDialogViewModel.self, result: String.self) { viewModel in
            recorder.recording(
                KmpModelBindingTestContentView(
                    notifier: try? kmp.notifier(for: viewModel, result: String.self)
                )
            )
        }

        let shown = SharedTestDialogViewModel(message: "表示中")
        let notShown = SharedTestDialogViewModel(message: "未表示")
        let showTask = Task { try await kmp.show(shown, result: String.self) }
        _ = try await recorder.view(at: 0)
        try #require(await harness.waitForPresentedContainers(count: 1))

        for viewModel in [shown, notShown] {
            #expect(throws: Self.intMismatch) {
                _ = try kmp.notifier(for: viewModel, result: Int.self)
            }
            #expect(throws: Self.uintMismatch) {
                _ = try kmp.notifier(for: viewModel, result: UInt.self)
            }
        }

        #expect(harness.presentedContainers.count == 1, "表示中のダイアログが閉じないこと")
        let notifier = try #require(try kmp.notifier(for: shown, result: String.self))
        notifier.complete("入力")
        #expect(try await showTask.value == .completed("入力"))
    }

    // MARK: Kotlin の整数型に対応する型 (IR-KM-07)

    /// 表示を待って報告口から値を返し、show の結果を返す。
    private func completeShownDialog<Result: Sendable>(
        _ showTask: Task<DialogResult<Result>, any Error>,
        recorder: DialogTestRecorder<Result>,
        harness: DialogTestHarness,
        value: Result
    ) async throws -> DialogResult<Result> {
        try #require(await harness.waitForPresentedContainers(count: 1))
        try await recorder.notifier(at: 0).complete(value)
        return try await showTask.value
    }

    @Test("[IR-KM-07] Kotlin の整数型に対応する Swift の型は今までどおり使える")
    func kotlinCompatibleIntegerTypesComplete() async throws {
        // 型ごとに具体型を直接書き、ジェネリックな入口に解決されることをビルドでも確かめる。
        do {
            let harness = DialogTestHarness()
            let recorder = DialogTestRecorder<Int32>()
            harness.dialogs.kmp.register(SharedTestDialogViewModel.self, result: Int32.self) { _, notifier in
                let view = DialogTestContentView()
                recorder.record(view: view, notifier: notifier)
                return view
            }
            let showTask = Task {
                try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "Int32"), result: Int32.self)
            }
            let result = try await completeShownDialog(showTask, recorder: recorder, harness: harness, value: -7)
            #expect(result == .completed(-7), "Kotlin の Int に対応する Int32")
        }
        do {
            let harness = DialogTestHarness()
            let recorder = DialogTestRecorder<Int64>()
            harness.dialogs.kmp.register(SharedTestDialogViewModel.self, result: Int64.self) { _, notifier in
                let view = DialogTestContentView()
                recorder.record(view: view, notifier: notifier)
                return view
            }
            let showTask = Task {
                try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "Int64"), result: Int64.self)
            }
            let result = try await completeShownDialog(
                showTask, recorder: recorder, harness: harness, value: Int64.max
            )
            #expect(result == .completed(Int64.max), "Kotlin の Long に対応する Int64")
        }
        do {
            let harness = DialogTestHarness()
            let recorder = DialogTestRecorder<UInt32>()
            harness.dialogs.kmp.register(SharedTestDialogViewModel.self, result: UInt32.self) { _, notifier in
                let view = DialogTestContentView()
                recorder.record(view: view, notifier: notifier)
                return view
            }
            let showTask = Task {
                try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "UInt32"), result: UInt32.self)
            }
            let result = try await completeShownDialog(showTask, recorder: recorder, harness: harness, value: 7)
            #expect(result == .completed(7), "Kotlin の UInt に対応する UInt32")
        }
        do {
            let harness = DialogTestHarness()
            let recorder = DialogTestRecorder<UInt64>()
            harness.dialogs.kmp.register(SharedTestDialogViewModel.self, result: UInt64.self) { _, notifier in
                let view = DialogTestContentView()
                recorder.record(view: view, notifier: notifier)
                return view
            }
            let showTask = Task {
                try await harness.dialogs.kmp.show(SharedTestDialogViewModel(message: "UInt64"), result: UInt64.self)
            }
            let result = try await completeShownDialog(
                showTask, recorder: recorder, harness: harness, value: UInt64.max
            )
            #expect(result == .completed(UInt64.max), "Kotlin の ULong に対応する UInt64")
        }
    }
}
#endif
