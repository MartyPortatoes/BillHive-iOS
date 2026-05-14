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

    /// Path where a single-month write is parked when the merge file is
    /// corrupt. Lets the user (or a future recovery flow) hand-merge.
    func recoverySidecarURL(for key: String) -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("monthly-recovery-\(key)-\(stamp).json")
    }

    // MARK: - State

    /// Loads the app state from disk.
    ///
    /// Returns an empty `AppState` when no file exists yet (fresh install).
    /// Throws when the file exists but cannot be read or decoded — callers
    /// must distinguish this from "no data" so users aren't misled into
    /// thinking their data vanished when it's actually corrupt.
    func loadState() throws -> AppState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return AppState()
        }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(AppState.self, from: data)
    }

    /// Writes the app state to disk as JSON.
    func saveState(_ state: AppState) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL)
        }
    }

    // MARK: - Monthly Data

    /// Loads all monthly data from disk.
    ///
    /// Returns an empty dictionary when no file exists yet. Throws when the
    /// file exists but cannot be read or decoded — same rationale as
    /// `loadState()`.
    func loadMonths() throws -> [String: MonthData] {
        guard FileManager.default.fileExists(atPath: monthlyURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: monthlyURL)
        return try JSONDecoder().decode([String: MonthData].self, from: data)
    }

    /// Merges the given month's data into the monthly file and writes to disk.
    ///
    /// Reads the existing file, updates the entry for `key`, and rewrites
    /// the entire file. This approach keeps all months in a single file for
    /// simplicity, matching the server's `/api/months` structure.
    ///
    /// If the existing file is corrupt, the merge would destroy every other
    /// month in the file. Instead we park the new month in a recovery
    /// sidecar (so the user's edit isn't lost) and throw so the caller can
    /// surface a toast. The corrupt file is left untouched for manual
    /// recovery.
    ///
    /// - Returns: A recovery sidecar URL if one had to be written, else nil.
    @discardableResult
    func saveMonth(_ key: String, data: MonthData) throws -> URL? {
        let months: [String: MonthData]
        do {
            months = try loadMonths()
        } catch {
            // Park the new value in a sidecar so the edit isn't lost.
            let sidecar = recoverySidecarURL(for: key)
            if let encoded = try? JSONEncoder().encode([key: data]) {
                try? encoded.write(to: sidecar)
            }
            throw error
        }
        var merged = months
        merged[key] = data
        if let encoded = try? JSONEncoder().encode(merged) {
            try? encoded.write(to: monthlyURL)
        }
        return nil
    }

    /// Overwrites the entire monthly file with the given dictionary.
    /// Used by the bulk-clear path so we don't have to enumerate keys.
    func saveAllMonths(_ months: [String: MonthData]) {
        if let encoded = try? JSONEncoder().encode(months) {
            try? encoded.write(to: monthlyURL)
        }
    }
}
