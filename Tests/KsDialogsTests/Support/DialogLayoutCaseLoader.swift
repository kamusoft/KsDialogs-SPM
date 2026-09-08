import Foundation

/// 共通ケース表 (リポジトリルートの `core/layout-spec/cases.json`) を読み込む。
///
/// 表は iOS / Android の両実装が参照する単一の正であり、
/// どちらのビルドルートにも属さないリポジトリルート直下に置かれている (core/ADR-0009)。
/// 期待値はこの表だけが持ち、テスト側に写しを作らない。
enum DialogLayoutCaseLoader {
    /// 読み込み済みのケース表。
    static let table: DialogLayoutCaseTable = loadTable()

    /// ケース表のファイル位置。
    static var caseTableURL: URL {
        repositoryRootURL.appendingPathComponent("core/layout-spec/cases.json")
    }

    /// このソースの位置からリポジトリルートを辿る (Support → KsDialogsTests → Tests → ios → ルート)。
    private static var repositoryRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// 読み込みに失敗したら黙って 0 件で通さず、その場で落として気づけるようにする。
    private static func loadTable() -> DialogLayoutCaseTable {
        let url = caseTableURL
        guard let data = try? Data(contentsOf: url) else {
            fatalError("共通ケース表を読み込めなかった: \(url.path)")
        }
        do {
            return try JSONDecoder().decode(DialogLayoutCaseTable.self, from: data)
        } catch {
            fatalError("共通ケース表を解釈できなかった: \(error)")
        }
    }
}
