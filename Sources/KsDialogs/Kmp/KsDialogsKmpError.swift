import Foundation

/// KMP 共有コードの ViewModel を扱う型付き入口だけが持つ失敗 (kmp/ADR-0004)。
///
/// 利用者の操作結果ではなくプログラミングエラーなので、cancelled に化けさせずに throw する。
/// 型消去輸送のために内部で使う印はこの面に出さない。
///
/// この判別は「共有 VM の紐付けと結果型の食い違い」だけを表す。ダイアログを提示できないなど、
/// 共有コード経路に固有でない失敗は `DialogError` のまま throw されるため、利用者は必要に応じて
/// そちらも捕まえる。判別の集合は利用者の網羅的な `switch` を左右するので、失敗の種類が増えても
/// この面は広げない。
public enum KsDialogsKmpError: Error, Equatable, Sendable {
    /// 共有 VM の型に対する View factory が登録されていない。
    case notRegistered(viewModelType: String)
    /// 結果値の型が、登録・show で指定した結果型 (省略時は真偽値) と一致しない。
    case resultTypeMismatch(expected: String, actual: String)
}

extension KsDialogsKmpError {
    /// ライブラリ内部の失敗を、KMP 向け型付き入口が throw する失敗へ写す。
    ///
    /// この面の判別に当たるものだけを写し替え、それ以外はライブラリ共通の公開エラーのまま素通しする。
    /// 判別のない失敗も理由を失わずに利用者へ届く。
    static func publicError(from error: (any Error)?) -> any Error {
        switch error as? DialogError {
        case .viewFactoryNotRegistered(let viewModelType):
            KsDialogsKmpError.notRegistered(viewModelType: viewModelType)
        case .resultTypeMismatch(let expected, let actual):
            KsDialogsKmpError.resultTypeMismatch(expected: expected, actual: actual)
        case .presentationHostUnavailable, .viewFactoryTypeMismatch,
             .viewModelFactoryNotRegistered, .viewModelFactoryTypeMismatch,
             .viewModelAlreadyShowing, .none:
            // 失敗の理由そのものを渡す。理由が欠けている結果は、提示できなかった失敗として扱う。
            error ?? DialogError.presentationHostUnavailable
        }
    }
}

extension KsDialogsKmpError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notRegistered(let viewModelType):
            "No View factory is registered for ViewModel type \(viewModelType)."
        case .resultTypeMismatch(let expected, let actual):
            "The result value type does not match (expected: \(expected) / actual: \(actual))."
        }
    }
}
