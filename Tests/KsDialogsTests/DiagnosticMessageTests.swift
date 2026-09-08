import Testing

@testable import KsDialogs

@Suite("失敗型の診断文言は英語固定")
struct DiagnosticMessageTests {
    /// 文言に埋め込まれる型名。実際の埋め込み値と同じく型名の文字列を渡す。
    private static let viewModelTypeName = "SampleDialogViewModel"
    private static let expectedTypeName = "Bool"
    private static let actualTypeName = "String"

    @Test("[DM-IO-01] DialogError の全 case が英語の説明文を返す")
    func dialogErrorDescriptionsAreEnglish() {
        let viewModelType = Self.viewModelTypeName
        let expectations: [(DialogError, String)] = [
            (
                .viewFactoryNotRegistered(viewModelType: viewModelType),
                "No View factory is registered for ViewModel type \(viewModelType)."
            ),
            (
                .presentationHostUnavailable,
                "No screen is available to present the Dialog."
            ),
            (
                .viewFactoryTypeMismatch(viewModelType: viewModelType),
                "The registered View factory cannot accept ViewModel type \(viewModelType)."
            ),
            (
                .resultTypeMismatch(expected: Self.expectedTypeName, actual: Self.actualTypeName),
                "The result value type does not match "
                    + "(expected: \(Self.expectedTypeName) / actual: \(Self.actualTypeName))."
            ),
            (
                .viewModelFactoryNotRegistered(viewModelType: viewModelType),
                "No ViewModel factory is registered for ViewModel type \(viewModelType)."
            ),
            (
                .viewModelFactoryTypeMismatch(viewModelType: viewModelType),
                "The registered ViewModel factory does not produce ViewModel type \(viewModelType)."
            ),
            (
                .viewModelAlreadyShowing(viewModelType: viewModelType),
                "This ViewModel instance of type \(viewModelType) is already being shown."
            ),
        ]

        // case の数だけ期待値を並べたことを固定する (case が増えたら期待値も足す)。
        #expect(expectations.count == 7)
        for (error, expected) in expectations {
            #expect(error.errorDescription == expected)
            #expect(error.localizedDescription == expected)
        }
    }

    @Test("[DM-IO-02] KsDialogsKmpError の全 case が英語の説明文を返す")
    func kmpErrorDescriptionsAreEnglish() {
        let viewModelType = Self.viewModelTypeName
        let expectations: [(KsDialogsKmpError, String)] = [
            (
                .notRegistered(viewModelType: viewModelType),
                "No View factory is registered for ViewModel type \(viewModelType)."
            ),
            (
                .resultTypeMismatch(expected: Self.expectedTypeName, actual: Self.actualTypeName),
                "The result value type does not match "
                    + "(expected: \(Self.expectedTypeName) / actual: \(Self.actualTypeName))."
            ),
        ]

        #expect(expectations.count == 2)
        for (error, expected) in expectations {
            #expect(error.errorDescription == expected)
            #expect(error.localizedDescription == expected)
        }
    }
}
