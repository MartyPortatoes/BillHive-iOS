import Foundation

struct MonthData: Codable {
    var totals: [String: Double]         // billId -> total
    var amounts: [String: [String: Double]] // billId -> lineId -> amount
    var _myTotal: Double?
    var _owes: [String: Double]?         // personId -> amount

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

    enum CodingKeys: String, CodingKey {
        case totals, amounts
        case _myTotal
        case _owes
    }
}

struct AppSettings: Codable {
    var myEmail: String
    var mortgageUrl: String
    var mortgageProvider: String

    init(myEmail: String = "", mortgageUrl: String = "", mortgageProvider: String = "") {
        self.myEmail = myEmail
        self.mortgageUrl = mortgageUrl
        self.mortgageProvider = mortgageProvider
    }
}

struct AppState: Codable {
    var settings: AppSettings
    var people: [Person]
    var bills: [Bill]
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

// Represents what one person owes for a given month
struct PersonOwes {
    var personId: String
    var total: Double
    var bills: [BillOwed]
}

struct BillOwed {
    var billId: String
    var billName: String
    var amount: Double
    var coveredNote: String? // e.g. "covers Mom"
}

// Month key helpers
struct MonthKey {
    static func current() -> String {
        let now = Date()
        let cal = Calendar.current
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        return String(format: "%04d-%02d", y, m)
    }

    static func from(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    static func label(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let m = Int(parts[1]),
              let y = Int(parts[0]) else { return key }
        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = 1
        if let date = Calendar.current.date(from: comps) {
            return df.string(from: date)
        }
        return key
    }

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
