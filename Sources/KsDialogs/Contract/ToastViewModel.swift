/// カスタム Toast の ViewModel が準拠する契約。
///
/// Toast は結果を返さず、進捗も持たない表示なので、`DialogViewModel` と違い結果型の宣言を持たず、
/// `LoadingViewModel` と違い進捗の受け口も持たない。データの運搬体とレジストリの型キーを兼ねる。
/// レジストリのキーはインスタンスではなく型の同一性で引くため、参照型 (class) 限定とする。
/// 同じ型を Dialog / Loading / Toast のどれで使ってもよい (レジストリは互いに独立しており、
/// 片方の登録が他方に影響しない)。
///
/// 表示は任意のスレッドから呼び出せるため、準拠する型は `Sendable` である必要がある。
public protocol ToastViewModel: AnyObject, Sendable {}
