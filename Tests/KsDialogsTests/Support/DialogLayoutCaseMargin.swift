@testable import KsDialogs

/// 共通ケース表の余白指定。全辺同値の数値と、辺ごとの指定の両方を受け付ける。
enum DialogLayoutCaseMargin: Decodable, Sendable {
    case uniform(Double)
    case edges(top: Double, left: Double, bottom: Double, right: Double)

    private enum CodingKeys: String, CodingKey {
        case top
        case left
        case bottom
        case right
    }

    init(from decoder: any Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let uniformValue = try? singleValue.decode(Double.self) {
            self = .uniform(uniformValue)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .edges(
            top: try container.decodeIfPresent(Double.self, forKey: .top) ?? 0,
            left: try container.decodeIfPresent(Double.self, forKey: .left) ?? 0,
            bottom: try container.decodeIfPresent(Double.self, forKey: .bottom) ?? 0,
            right: try container.decodeIfPresent(Double.self, forKey: .right) ?? 0
        )
    }

    /// 契約側の余白表現へ変換する。
    var insets: DialogEdgeInsets {
        switch self {
        case .uniform(let value):
            return DialogEdgeInsets(all: value)
        case .edges(let top, let left, let bottom, let right):
            return DialogEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        }
    }
}
