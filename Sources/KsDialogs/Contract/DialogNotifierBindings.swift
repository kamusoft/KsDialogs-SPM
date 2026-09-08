import Foundation

/// 表示中の ViewModel と結果チャネルを結ぶ紐付け表 (core/ADR-0018)。
///
/// ViewModel の定義を空のまま保つため、報告口の置き場を ViewModel の外に持つ。
/// キーはインスタンスの同一性 (`ObjectIdentifier`) であり、等価比較には依存しない —
/// 等価な別インスタンスは別の紐付けとして扱われる。
///
/// 紐付けは show が中身を生成する直前に作り、show が終わる全経路で外す。
/// 保持は弱参照で、除去漏れが起きても ViewModel の解放とともに空振りする安全網になる。
/// `ObjectIdentifier` は解放済みインスタンスのアドレスを再利用しうるため、
/// 取得時に弱参照の生存と同一性を確かめる。
final class DialogNotifierBindings: @unchecked Sendable {
    /// 全入口が共有する紐付け表。
    static let shared = DialogNotifierBindings()

    /// 1回の show 分の紐付け。
    struct Binding {
        weak var viewModel: AnyObject?
        let resultChannel: DialogResultChannel
        /// show を始めた時点の factory が固定していた結果型。
        /// ViewModel 自身が結果型を宣言する経路では持たない。
        let declaredResultType: DialogDeclaredResultType?
    }

    private let lock = NSLock()
    private var bindings: [ObjectIdentifier: Binding] = [:]

    /// ViewModel に結果チャネルを紐付ける。
    /// `declaredResultType` は show が使う factory の宣言結果型で、表示中の型検証はこの値を使う —
    /// 表示中に同じ ViewModel 型が別の結果型で登録し直されても、既に出ているダイアログの
    /// 報告口は show を始めた時点の型のまま引ける。
    /// - Returns: 紐付けられたら true。同じインスタンスが既に表示中なら false (並行 show の検出)
    func bind(
        _ viewModel: AnyObject,
        to resultChannel: DialogResultChannel,
        declaredResultType: DialogDeclaredResultType? = nil
    ) -> Bool {
        let key = ObjectIdentifier(viewModel)
        lock.lock()
        defer { lock.unlock() }
        if let existing = bindings[key], existing.viewModel != nil {
            return false
        }
        bindings[key] = Binding(
            viewModel: viewModel,
            resultChannel: resultChannel,
            declaredResultType: declaredResultType
        )
        return true
    }

    /// 紐付けを外す。別の show が作った紐付けは外さない。
    func unbind(_ viewModel: AnyObject, resultChannel: DialogResultChannel) {
        let key = ObjectIdentifier(viewModel)
        lock.lock()
        defer { lock.unlock() }
        guard let existing = bindings[key], existing.resultChannel === resultChannel else { return }
        bindings.removeValue(forKey: key)
    }

    /// ViewModel に紐付いている結果チャネル。表示中でなければ nil。
    func resultChannel(for viewModel: AnyObject) -> DialogResultChannel? {
        binding(for: viewModel)?.resultChannel
    }

    /// ViewModel に紐付いている show 1回分の情報。表示中でなければ nil。
    func binding(for viewModel: AnyObject) -> Binding? {
        let key = ObjectIdentifier(viewModel)
        lock.lock()
        defer { lock.unlock() }
        guard let existing = bindings[key] else { return nil }
        guard let boundViewModel = existing.viewModel, boundViewModel === viewModel else {
            // 解放済みインスタンスのアドレス再利用。残骸を掃除して未紐付けとして扱う。
            bindings.removeValue(forKey: key)
            return nil
        }
        return existing
    }
}
