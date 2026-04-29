import Foundation

// MARK: - Local Storage Manager

/// Persists app state and monthly data to the app's Documents directory as JSON files.
///
/// Used as the primary storage backend for the SelfHive target (when iCloud is
/// unavailable) and as a fallback/backup for the BillHive target's cloud storage.
///
/// File layout:
/// - `Documents/state.json` — the complete `AppState` (people, bills, settings)
/// - `Documents/monthly.json` — all `MonthData` keyed by month string
class LocalStorageManager {
    static let shared = LocalStorageManager()
    private init() {}

    // MARK: - File URLs

    private var stateURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("state.json")
    }

    private var monthlyURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("monthly.json")
    }

    // MARK: - State

    /// Loads the app state from disk, returning an empty default if the file
    /// doesn't exist or can't be decoded.
    func loadState() -> AppState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState()
        }
        return state
    }

    /// Writes the app state to disk as JSON.
    func saveState(_ state: AppState) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL)
        }
    }

    // MARK: - Monthly Data

    /// Loads all monthly data from disk, returning an empty dictionary if the
    /// file doesn't exist or can't be decoded.
    func loadMonths() -> [String: MonthData] {
        guard let data = try? Data(contentsOf: monthlyURL),
              let months = try? JSONDecoder().decode([String: MonthData].self, from: data) else {
            return [:]
        }
        return months
    }

    /// Merges the given month's data into the monthly file and writes to disk.
    ///
    /// Reads the existing file, updates the entry for `key`, and rewrites
    /// the entire file. This approach keeps all months in a single file for
    /// simplicity, matching the server's `/api/months` structure.
    func saveMonth(_ key: String, data: MonthData) {
        var months = loadMonths()
        months[key] = data
        if let encoded = try? JSONEncoder().encode(months) {
            try? encoded.write(to: monthlyURL)
        }
    }

    /// Overwrites the entire monthly file with the given dictionary.
    /// Used by the bulk-clear path so we don't have to enumerate keys.
    func saveAllMonths(_ months: [String: MonthData]) {
        if let encoded = try? JSONEncoder().encode(months) {
            try? encoded.write(to: monthlyURL)
        }
    }
}
