import Foundation

// MARK: - Split Type

/// Defines how a bill's total is divided among its line items.
///
/// - `pct`: Each line holds a percentage (0–100). The dollar amount for each
///   line is computed as `total * line.value / 100`.
/// - `fixed`: Each line holds a fixed dollar amount. One line may be designated
///   as the "remainder" line, which automatically receives `total − sum(others)`.
enum SplitType: String, Codable, CaseIterable, Sendable {
    case pct = "pct"
    case fixed = "fixed"

    /// Human-readable label for display in pickers and UI badges.
    var displayName: String {
        switch self {
        case .pct: return "Percentage"
        case .fixed: return "Fixed"
        }
    }
}

// MARK: - Bill Line

/// A single person's share within a bill.
///
/// In percentage mode, `value` represents the percentage (0–100) of the bill
/// total that this person owes. In fixed mode, the dollar amount for each line
/// is stored separately in `MonthData.amounts` so it can vary month-to-month
/// without changing the bill configuration.
struct BillLine: Identifiable, Codable, Equatable, Sendable {
    var id: String
    /// Short description of this line (e.g. "My share", "Internet portion").
    var desc: String
    /// The person responsible for this line item.
    var personId: String
    /// In pct mode: the percentage (0–100). In fixed mode: unused (amounts live in MonthData).
    var value: Double
    /// When set, another person covers this line's cost on behalf of `personId`.
    /// The amount is attributed to `coveredById` in all split calculations.
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

// MARK: - Bill

/// A recurring bill that is split among household members.
///
/// Bills are part of `AppState` and persist across months. The actual dollar
/// amounts for each month are stored separately in `MonthData`, allowing the
/// same bill configuration to carry different totals each month.
struct Bill: Identifiable, Codable, Equatable, Sendable {
    var id: String
    /// Display name (e.g. "Rent", "Electric").
    var name: String
    /// Emoji icon shown in the bill card header.
    var icon: String
    /// Hex color string (e.g. "#F5A800") for the bill's accent color.
    var color: String
    /// How this bill is divided among its line items.
    var splitType: SplitType
    /// In fixed-split mode, the line that receives the leftover amount
    /// after all other fixed lines are subtracted from the total.
    var remainderLineId: String
    /// Optional URL to the bill's payment portal (e.g. utility company website).
    var payUrl: String
    /// When true, the previous month's amounts are auto-copied into a new month.
    var preserve: Bool
    /// When true, this bill is paid automatically — skips the "paid" checklist task.
    var autoPay: Bool
    /// Day of the month (1–31) when this bill is due. `nil` means no due date set.
    var dueDay: Int?
    /// Who actually pays this bill to the provider. Defaults to "me".
    /// When set to another person, their share is self-covered and
    /// the primary user's share becomes something they owe that person.
    var paidById: String
    /// The individual share lines for this bill.
    var lines: [BillLine]

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, splitType, remainderLineId, payUrl, preserve, autoPay, dueDay, paidById, lines
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
        autoPay = try c.decodeIfPresent(Bool.self, forKey: .autoPay) ?? false
        dueDay = try c.decodeIfPresent(Int.self, forKey: .dueDay)
        paidById = try c.decodeIfPresent(String.self, forKey: .paidById) ?? "me"
        lines = try c.decode([BillLine].self, forKey: .lines)
    }

    /// Creates a new bill with sensible defaults.
    ///
    /// If no lines are provided, a single "My share" line is created
    /// automatically and designated as the remainder line.
    init(
        id: String = "b\(Int(Date().timeIntervalSince1970 * 1000))",
        name: String = "New Bill",
        icon: String = "💰",
        color: String = "#F5A800",
        splitType: SplitType = .pct,
        remainderLineId: String = "",
        payUrl: String = "",
        preserve: Bool = false,
        autoPay: Bool = false,
        dueDay: Int? = nil,
        paidById: String = "me",
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
        self.autoPay = autoPay
        self.dueDay = dueDay
        self.paidById = paidById
        if lines.isEmpty {
            let lineId = "l\(Int(Date().timeIntervalSince1970 * 1000))"
            self.lines = [BillLine(id: lineId, desc: "My share", personId: "me", value: 100)]
            self.remainderLineId = lineId
        } else {
            self.lines = lines
        }
    }

    // MARK: - Due Date Helpers

    /// Ordinal suffix for the due day (e.g. "1st", "2nd", "15th").
    var dueDayLabel: String? {
        guard let day = dueDay else { return nil }
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }
        return "\(day)\(suffix)"
    }

    /// Urgency level for the due date relative to today within the given
    /// month/year context. Returns `nil` when no `dueDay` is set.
    enum DueUrgency {
        case overdue
        case soon      // within 3 days
        case upcoming  // more than 3 days away
    }

    func dueUrgency(month: Int, year: Int) -> DueUrgency? {
        guard let day = dueDay else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayComps = cal.dateComponents([.month, .year, .day], from: today)
        guard let todayMonth = todayComps.month,
              let todayYear = todayComps.year,
              let todayDay = todayComps.day else { return nil }

        // Only compute urgency for the current calendar month
        guard month == todayMonth && year == todayYear else { return .upcoming }

        let daysUntil = day - todayDay

        if daysUntil < 0 { return .overdue }
        if daysUntil <= 3 { return .soon }
        return .upcoming
    }
}
