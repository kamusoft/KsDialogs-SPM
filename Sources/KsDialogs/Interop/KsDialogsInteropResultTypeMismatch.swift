#if canImport(UIKit)

/// 報告された結果値が宣言結果型と合わなかったことを、型消去輸送の中で運ぶための印。
///
/// 結果チャネルは値の型を見ないため、不一致もいったん結果として確定させ、
/// 互換面が結果を組み立てるところで失敗の判別へ振り替える。
/// これによりダイアログは閉じ、呼び出し元は cancelled ではなく失敗を受け取る。
struct KsDialogsInteropResultTypeMismatch {
    /// 登録時に宣言された結果型の名前。
    let expected: String
    /// 実際に報告された値の型の名前。
    let actual: String

    /// 委譲元へ返す失敗理由。
    var error: DialogError {
        .resultTypeMismatch(expected: expected, actual: actual)
    }
}
#endif
