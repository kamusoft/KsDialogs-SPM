@testable import KsDialogs

/// 同じラベルを持つ別インスタンスどうしが等価になる ViewModel。
/// 結果報告口の紐付けが等価比較ではなくインスタンスの同一性で行われることを確かめるために使う。
final class EquatableTestDialogViewModel: DialogViewModel, Hashable {
    typealias Result = Bool

    let label: String

    init(label: String) {
        self.label = label
    }

    static func == (lhs: EquatableTestDialogViewModel, rhs: EquatableTestDialogViewModel) -> Bool {
        lhs.label == rhs.label
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
    }
}
