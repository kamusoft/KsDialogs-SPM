/// ダイアログの ViewModel が準拠する契約。
/// 結果型は呼び出し側ではなく ViewModel 自身が `Result` として宣言し、
/// show の戻り値と結果報告部品の型はここから導出される。
///
/// ViewModel は結果と状態の運び手であり、レイアウト属性は持たない。
/// ダイアログの大きさや置き場所は中身の View への添付 (`ksDialogOptions` / `ksDialogPlacement`) と
/// show の placement 引数で供給する (core/ADR-0015)。
///
/// 準拠できるのは参照型 (class) だけである。表示中の結果報告口 (`notifier`) を
/// インスタンスの同一性で引くため、値のコピーで同一性が失われる型は扱えない (core/ADR-0018)。
///
/// show は任意のスレッドから呼び出せるため、準拠する型は `Sendable` である必要がある。
/// (`@MainActor` を付けた final class も暗黙に `Sendable` を満たす)
public protocol DialogViewModel: AnyObject, Sendable {
    /// この ViewModel が宣言する結果値の型。
    /// 宣言を省略した ViewModel の結果は真偽値になる (core/ADR-0012)。
    associatedtype Result: Sendable = Bool
}

public extension DialogViewModel {
    /// 表示中のこの ViewModel に紐付いた結果報告口 (core/ADR-0018)。
    ///
    /// show が中身を生成する直前に紐付き、結果が呼び出し元へ渡る前に外れる。
    /// したがって show の前と終わったあとは nil であり、表示中だけ値を返す。
    /// 型は ViewModel の宣言結果型に固定され、factory の引数で渡される報告口と同じ配送先を指す。
    ///
    ///     final class ConfirmViewModel: DialogViewModel {
    ///         func tapOK() { notifier?.complete(true) }
    ///     }
    var notifier: DialogNotifier<Result>? {
        guard let resultChannel = DialogNotifierBindings.shared.resultChannel(for: self) else {
            return nil
        }
        return DialogNotifier(resultChannel: resultChannel)
    }
}
