/// カスタム Loading の ViewModel が準拠する契約。
///
/// Loading は結果を返さないライフサイクルなので、`DialogViewModel` と違い結果型の宣言を持たない。
/// レジストリのキーはインスタンスではなく型の同一性で引くため、Dialog と同じく参照型 (class) 限定とする。
/// 同じ型を Dialog と Loading の両方で使いたい場合は、両方の契約に準拠させる
/// (レジストリは互いに独立しており、片方の登録が他方に影響しない)。
///
/// 表示は任意のスレッドから呼び出せるため、準拠する型は `Sendable` である必要がある。
public protocol LoadingViewModel: AnyObject, Sendable {}
