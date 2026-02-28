import Foundation

class LocalStorageManager {
    static let shared = LocalStorageManager()
    private init() {}

    private var stateURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("state.json")
    }

    private var monthlyURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("monthly.json")
    }

    func loadState() -> AppState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState()
        }
        return state
    }

    func saveState(_ state: AppState) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL)
        }
    }

    func loadMonths() -> [String: MonthData] {
        guard let data = try? Data(contentsOf: monthlyURL),
              let months = try? JSONDecoder().decode([String: MonthData].self, from: data) else {
            return [:]
        }
        return months
    }

    func saveMonth(_ key: String, data: MonthData) {
        var months = loadMonths()
        months[key] = data
        if let encoded = try? JSONEncoder().encode(months) {
            try? encoded.write(to: monthlyURL)
        }
    }
}
