/// KMP 共有コードの ViewModel を模した検証用の型。
///
/// 共有コードの ViewModel は iOS Native の ViewModel 契約に準拠せず、結果型も宣言しない。
/// KMP 向け公開面が「契約に準拠しないクラス」を扱えることを確かめるため、素のクラスにしてある。
final class SharedTestDialogViewModel {
    let message: String

    init(message: String) {
        self.message = message
    }
}
