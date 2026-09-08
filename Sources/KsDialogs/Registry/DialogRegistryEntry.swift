#if canImport(UIKit)

/// ViewModel 型1つ分のレジストリのエントリ (core/ADR-0021)。
///
/// View factory と ViewModel factory の2スロットを持ち、再登録は**スロット単位の後勝ち**で
/// 該当スロットだけを置き換える。片方だけを登録し直しても、もう片方は保持される。
struct DialogRegistryEntry {
    /// 中身を生成する factory。インスタンス渡し show と型指定 show の両方が使う。
    var viewFactory: DialogViewFactory?

    /// ViewModel を生成する factory。型指定 show だけが使う。
    var viewModelFactory: DialogViewModelFactory?
}
#endif
