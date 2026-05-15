import Foundation

// MARK: - Month Data

/// Per-month financial data — bill totals and individual line amounts.
///
/// Each month key (e.g. "2026-03") maps to one `MonthData` instance.
/// This separation from `AppState` allows the bill *configuration* (names,
/// split types, people) to persist independently from the *dollar amounts*
/// that change each month.
struct MonthData: Codable, Equatable, Sendable {
    /// Bill totals keyed by bill ID. Example: `["b123": 1500.00]`.
    var totals: [String: Double]
    /// Per-line amounts keyed by bill ID then line ID.
    /// Example: `["b123": ["l1": 750.00, "l2": 750.00]]`.
    var amounts: [String: [String: Double]]
    /// Cached "my total" for the historical trends view.
    /// Computed at save time via `computeMyTotal()`.
    var _myTotal: Double?
    /// Cached per-person owes for the historical trends view.
    /// Keyed by person ID. Computed at save time via `computePersonOwes()`.
    var _owes: [String: Double]?

    init(
        totals: [String: Double] = [:],
        amounts: [String: [String: Double]] = [:],
        myTotal: Double? = nil,
        owes: [String: Double]? = nil
    ) {
        self.totals = totals
        self.amounts = amounts
        self._myTotal = myTotal
        self._owes = owes
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case totals, amounts
        case _myTotal
        case _owes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totals = try c.decodeIfPresent([String: Double].self, forKey: .totals) ?? [:]
        amounts = try c.decodeIfPresent([String: [String: Double]].self, forKey: .amounts) ?? [:]
        _myTotal = try c.decodeIfPresent(Double.self, forKey: ._myTotal)
        _owes = try c.decodeIfPresent([String: Double].self, forKey: ._owes)
    }
}

// MARK: - App Settings

/// User-level settings that persist across months.
struct AppSettings: Codable, Equatable, Sendable {
    /// The primary user's email address.
    var myEmail: String
    /// URL to the mortgage payment portal (shown as a quick-pay link).
    var mortgageUrl: String
    /// Display name for the mortgage provider.
    var mortgageProvider: String
    /// ISO 4217 currency code (e.g. "USD", "EUR"). Empty string means auto-detect from device locale.
    var currencyCode: String

    init(myEmail: String = "", mortgageUrl: String = "", mortgageProvider: String = "", currencyCode: String = "") {
        self.myEmail = myEmail
        self.mortgageUrl = mortgageUrl
        self.mortgageProvider = mortgageProvider
        self.currencyCode = currencyCode
    }

    enum CodingKeys: String, CodingKey {
        case myEmail, mortgageUrl, mortgageProvider, currencyCode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        myEmail = try c.decodeIfPresent(String.self, forKey: .myEmail) ?? ""
        mortgageUrl = try c.decodeIfPresent(String.self, forKey: .mortgageUrl) ?? ""
        mortgageProvider = try c.decodeIfPresent(String.self, forKey: .mortgageProvider) ?? ""
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? ""
    }
}

// MARK: - App State

/// The complete application configuration — people, bills, settings, and checklists.
///
/// This is the "shape" of the data, independent of any particular month's dollar
/// amounts. Persisted as `state.json` locally or via the server's `/api/state` endpoint.
struct AppState: Codable, Equatable, Sendable {
    var settings: AppSettings
    /// All household members. The first entry (id == "me") is always the primary user.
    var people: [Person]
    /// All configured bills.
    var bills: [Bill]
    /// Monthly checklists keyed by month key (e.g. "2026-03"), then item ID → done state.
    var checklist: [String: [String: Bool]]

    init(
        settings: AppSettings = AppSettings(),
        people: [Person] = [],
        bills: [Bill] = [],
        checklist: [String: [String: Bool]] = [:]
    ) {
        self.settings = settings
        self.people = people
        self.bills = bills
        self.checklist = checklist
    }
}

// MARK: - Person Owes (Computed)

/// What a single person owes for the current month, with a per-bill breakdown.
///
/// This is a computed view-model type — not persisted. Built by
/// `AppViewModel.computePersonOwes()` each time the summary is displayed.
struct PersonOwes {
    var personId: String
    var total: Double
    var bills: [BillOwed]
}

/// A single bill's contribution to what a person owes.
struct BillOwed {
    var billId: String
    var billName: String
    var amount: Double
    /// Explanatory note when someone covers another person's share (e.g. "covers Mom").
    var coveredNote: String?
}

/// A settlement between two non-primary people (neither is "me").
struct ThirdPartySettlement: Identifiable {
    var id: String { "\(fromId)_\(toId)" }
    var fromId: String
    var toId: String
    var amount: Double
    var bills: [BillOwed]
}

// MARK: - Month Key Helpers

/// Utility for creating and manipulating month keys in "YYYY-MM" format.
struct MonthKey {

    // MARK: - Cached Formatters

    /// Cached formatter for `label()` — avoids allocating a new `DateFormatter`
    /// on every call. Thread-safe because `DateFormatter` is a class, and this
    /// static is initialized once lazily by the runtime.
    private static let monthYearFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        return df
    }()

    // MARK: - Factory Methods

    /// Returns the current month key (e.g. "2026-03").
    static func current() -> String {
        let now = Date()
        let cal = Calendar.current
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        return String(format: "%04d-%02d", y, m)
    }

    /// Creates a month key from year and month components.
    static func from(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    // MARK: - Display

    /// Converts a month key into a human-readable label (e.g. "March 2026").
    static func label(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let m = Int(parts[1]),
              let y = Int(parts[0]) else { return key }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = 1
        if let date = Calendar.current.date(from: comps) {
            return monthYearFormatter.string(from: date)
        }
        return key
    }

    // MARK: - Navigation

    /// Returns the month key for the month before `key`.
    ///
    /// Handles year rollover (e.g. "2026-01" → "2025-12").
    static func previous(of key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              var m = Int(parts[1]),
              var y = Int(parts[0]) else { return key }
        m -= 1
        if m < 1 { m = 12; y -= 1 }
        return String(format: "%04d-%02d", y, m)
    }
}
