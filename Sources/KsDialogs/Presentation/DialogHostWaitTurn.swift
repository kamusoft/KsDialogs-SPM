#if canImport(UIKit)
/// 提示先を待った show の番の結末。
enum DialogHostWaitTurn {
    /// 提示してよい。
    ///
    /// 列から明けた show は、提示が終わるまで列の番を持つ (`slot`)。提示が終わったら
    /// `slot.finish()` で番を返し、次の 1 枚を明けさせる。待たずに提示へ進んだ show は番を持たない (nil)。
    case ready(DialogHostWaitSlot?)

    /// 待っている間に結果が確定した (呼び出し元の打ち切りを含む)。中身を作らずに終える。
    case settled
}
#endif
