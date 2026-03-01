import Foundation

enum SplitType: String, Codable, CaseIterable {
    case pct = "pct"
    case fixed = "fixed"

    var displayName: String {
        switch self {
        case .pct: return "Percentage"
        case .fixed: return "Fixed"
        }
    }
}

struct BillLine: Identifiable, Codable, Equatable {
    var id: String
    var desc: String
    var personId: String
    var value: Double      // pct mode: 0-100
    var coveredById: String?

    init(
        id: String = "l\(Int(Date().timeIntervalSince1970 * 1000))",
        desc: String = "Line",
        personId: String = "me",
        value: Double = 100,
        coveredById: String? = nil
    ) {
        self.id = id
        self.desc = desc
        self.personId = personId
        self.value = value
        self.coveredById = coveredById
    }
}

struct Bill: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String
    var color: String
    var splitType: SplitType
    var remainderLineId: String
    var payUrl: String
    var preserve: Bool
    var lines: [BillLine]

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, splitType, remainderLineId, payUrl, preserve, lines
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decode(String.self, forKey: .icon)
        color = try c.decode(String.self, forKey: .color)
        splitType = try c.decode(SplitType.self, forKey: .splitType)
        remainderLineId = try c.decode(String.self, forKey: .remainderLineId)
        payUrl = try c.decodeIfPresent(String.self, forKey: .payUrl) ?? ""
        preserve = try c.decodeIfPresent(Bool.self, forKey: .preserve) ?? false
        lines = try c.decode([BillLine].self, forKey: .lines)
    }

    init(
        id: String = "b\(Int(Date().timeIntervalSince1970 * 1000))",
        name: String = "New Bill",
        icon: String = "💰",
        color: String = "#F5A800",
        splitType: SplitType = .pct,
        remainderLineId: String = "",
        payUrl: String = "",
        preserve: Bool = false,
        lines: [BillLine] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.splitType = splitType
        self.remainderLineId = remainderLineId
        self.payUrl = payUrl
        self.preserve = preserve
        if lines.isEmpty {
            let lineId = "l\(Int(Date().timeIntervalSince1970 * 1000))"
            self.lines = [BillLine(id: lineId, desc: "My share", personId: "me", value: 100)]
            self.remainderLineId = lineId
        } else {
            self.lines = lines
        }
    }
}
