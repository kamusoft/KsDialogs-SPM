/// レジストリのキー。ViewModel のメタタイプの同一性だけで決まる (リフレクションは使わない。core/ADR-0004)。
///
/// Swift の型付き登録 (メタタイプ) と ObjC 互換面の登録 (クラスオブジェクト) が同じキー空間に載るため、
/// どちらの入口から登録しても同一のレジストリで解決できる。
struct DialogViewModelKey: Hashable {
    private let typeIdentifier: ObjectIdentifier

    init(_ viewModelType: Any.Type) {
        typeIdentifier = ObjectIdentifier(viewModelType)
    }
}
