/// 登録のときに固定された結果値の型。
///
/// ViewModel 契約に準拠しない ViewModel (KMP 共有コードのもの) は結果型を自分で宣言しないため、
/// 登録で受け取った型をここに控えておき、結果報告口を引くときの型指定と突き合わせる。
///
/// 同一性は型そのもので見る。名前は食い違いを説明するためだけに持つ。
struct DialogDeclaredResultType: Equatable, Sendable {
    private let identifier: ObjectIdentifier

    /// 結果型の名前。
    let name: String

    init(_ resultType: Any.Type) {
        identifier = ObjectIdentifier(resultType)
        name = String(describing: resultType)
    }
}
