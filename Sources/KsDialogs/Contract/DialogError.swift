import Foundation

/// show が結果 (completed / cancelled) を返せない構成エラー。
/// 利用者の操作結果ではなくプログラミングエラーであり、cancelled に化けさせずに throw する。
public enum DialogError: Error, Equatable, Sendable {
    /// ViewModel 型に対する View factory がレジストリに登録されていない。
    case viewFactoryNotRegistered(viewModelType: String)
    /// アクティブな提示先の画面が存在しない。キューイングはせず即座に失敗する。
    case presentationHostUnavailable
    /// 登録済み factory が ViewModel の実際の型を受け取れない (型消去輸送での不整合)。
    case viewFactoryTypeMismatch(viewModelType: String)
    /// 報告された結果値が ViewModel の宣言結果型へ復元できない (型消去輸送での不整合)。
    case resultTypeMismatch(expected: String, actual: String)
    /// ViewModel 型に対する ViewModel factory がレジストリに登録されていない (型指定 show の構成ミス)。
    case viewModelFactoryNotRegistered(viewModelType: String)
    /// 登録済み ViewModel factory が要求された型の ViewModel を作らない (型消去輸送での不整合)。
    case viewModelFactoryTypeMismatch(viewModelType: String)
    /// 表示中の ViewModel インスタンスを重ねて show しようとした。
    /// 結果報告口はインスタンスに1つだけ紐付くため、同じインスタンスの並行表示は成立しない。
    case viewModelAlreadyShowing(viewModelType: String)
}

// 失敗の説明文 (診断文言) は英語固定でローカライズしない (cross/ADR-0015)。
extension DialogError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .viewFactoryNotRegistered(let viewModelType):
            "No View factory is registered for ViewModel type \(viewModelType)."
        case .presentationHostUnavailable:
            "No screen is available to present the Dialog."
        case .viewFactoryTypeMismatch(let viewModelType):
            "The registered View factory cannot accept ViewModel type \(viewModelType)."
        case .resultTypeMismatch(let expected, let actual):
            "The result value type does not match (expected: \(expected) / actual: \(actual))."
        case .viewModelFactoryNotRegistered(let viewModelType):
            "No ViewModel factory is registered for ViewModel type \(viewModelType)."
        case .viewModelFactoryTypeMismatch(let viewModelType):
            "The registered ViewModel factory does not produce ViewModel type \(viewModelType)."
        case .viewModelAlreadyShowing(let viewModelType):
            "This ViewModel instance of type \(viewModelType) is already being shown."
        }
    }
}
