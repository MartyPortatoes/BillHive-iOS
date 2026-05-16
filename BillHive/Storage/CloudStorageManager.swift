import Foundation

// MARK: - Cloud Storage Manager

/// Manages iCloud Document storage for the BillHive standalone target.
///
/// Syncs `state.json` and `monthly.json` across devices via iCloud Drive using
/// `NSFileCoordinator` for safe concurrent access. Falls back to
/// `LocalStorageManager` when iCloud is unavailable (e.g. user not signed in,
/// or running in the simulator without iCloud entitlement).
///
/// ## File Layout (inside iCloud container)
/// ```
/// iCloud.com.billhive.app/
///   Documents/
///     state.json     — AppState (people, bills, settings, checklists)
///     monthly.json   — All MonthData keyed by month string
/// ```
///
/// ## Change Monitoring
/// An `NSMetadataQuery` watches for `.json` file updates in the ubiquitous
/// documents scope. When another device pushes changes, the query fires a
/// notification (`filesDidChangeExternally`) that `AppViewModel` observes
/// to reload data.
class CloudStorageManager: NSObject {
    static let shared = CloudStorageManager()

    /// Posted when iCloud delivers updated files from another device.
    /// Observers should reload state and monthly data when this fires.
    static let filesDidChangeExternally = Notification.Name("CloudStorageFilesDidChange")

    private let containerID = "iCloud.com.billhive.app"
    private let stateFilename = "state.json"
    private let monthlyFilename = "monthly.json"

    /// Cached ubiquity container URL. `nil` means iCloud is unavailable.
    private var iCloudURL: URL?
    /// Metadata query that monitors iCloud for file changes from other devices.
    private var metadataQuery: NSMetadataQuery?

    /// Timestamp of the last write this process issued. Used by
    /// `queryDidUpdate` to suppress the feedback loop where our own
    /// iCloud writes echo back through `NSMetadataQuery` and trigger a
    /// redundant `reloadFromCloud()` (which is two coordinated reads
    /// every time, even when state hasn't actually changed).
    private var lastSelfWriteAt: Date = .distantPast
    /// How long after a self-write to treat metadata updates as our own
    /// echo and ignore them. A genuine cross-device change arriving in
    /// this window will be missed until the next scene-active reload
    /// (`BillHiveApp.swift`); the trade-off is worth it because the
    /// feedback fires after every keystroke during editing.
    private let selfWriteSuppressionWindow: TimeInterval = 2.0

    private override init() {
        super.init()
        // url(forUbiquityContainerIdentifier:) returns nil if iCloud is unavailable
        // and creates the container directory if it doesn't exist yet.
        iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: containerID)
        if iCloudURL != nil {
            startMonitoring()
        }
    }

    /// Whether iCloud storage is active (vs local-only fallback).
    var isCloudAvailable: Bool { iCloudURL != nil }

    // MARK: - Documents Directory

    private var cloudDocsURL: URL? {
        iCloudURL?.appendingPathComponent("Documents")
    }

    private var cloudStateURL: URL? {
        cloudDocsURL?.appendingPathComponent(stateFilename)
    }

    private var cloudMonthlyURL: URL? {
        cloudDocsURL?.appendingPathComponent(monthlyFilename)
    }

    // MARK: - Public API

    /// Loads the app state from iCloud, falling back to the local backup if
    /// iCloud is unavailable, not yet downloaded, or holds an unreadable file.
    ///
    /// Throws only when the local backup itself is corrupt — i.e. no recovery
    /// path remains. Cloud-only corruption falls through silently because
    /// `saveState()` always writes a local backup, and the cloud copy will be
    /// overwritten on the next save.
    func loadState() throws -> AppState {
        guard let fileURL = cloudStateURL else {
            return try LocalStorageManager.shared.loadState()
        }
        triggerDownloadIfNeeded(fileURL)
        if let data = coordinatedRead(at: fileURL),
           let state = try? JSONDecoder().decode(AppState.self, from: data) {
            return state
        }
        return try LocalStorageManager.shared.loadState()
    }

    /// Saves the app state to both iCloud and local storage (backup).
    ///
    /// The iCloud write hops off the main thread because `NSFileCoordinator`
    /// is synchronous and can stall the caller for tens to hundreds of ms
    /// while it talks to the iCloud daemon on ubiquity-tracked files.
    func saveState(_ state: AppState) async {
        // Always keep a local copy as backup in case iCloud becomes unavailable.
        // Local disk writes are quick, so we do them on the calling thread.
        LocalStorageManager.shared.saveState(state)

        guard let fileURL = cloudStateURL else { return }
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        ensureCloudDocsDir()
        lastSelfWriteAt = Date()
        await Self.coordinatedWriteOffMain(data: encoded, to: fileURL)
    }

    /// Loads all monthly data from iCloud, falling back to the local backup
    /// if iCloud is unavailable, not yet downloaded, or holds an unreadable
    /// file. Throws only when the local backup is also unreadable.
    func loadMonths() throws -> [String: MonthData] {
        guard let fileURL = cloudMonthlyURL else {
            return try LocalStorageManager.shared.loadMonths()
        }
        triggerDownloadIfNeeded(fileURL)
        if let data = coordinatedRead(at: fileURL),
           let months = try? JSONDecoder().decode([String: MonthData].self, from: data) {
            return months
        }
        return try LocalStorageManager.shared.loadMonths()
    }

    /// Saves a single month's data, merging it into the existing monthly file.
    ///
    /// Reads the current months from iCloud, updates the entry for `key`,
    /// and rewrites the file. Also saves to local storage as backup.
    ///
    /// If the existing months file is corrupt, throws — overwriting would
    /// destroy every other month. `LocalStorageManager.saveMonth` parks a
    /// recovery sidecar before throwing, so the new value isn't lost.
    func saveMonth(_ key: String, data: MonthData) throws {
        try LocalStorageManager.shared.saveMonth(key, data: data)

        guard let fileURL = cloudMonthlyURL else { return }
        let existing = try loadMonths()
        var months = existing
        months[key] = data
        guard let encoded = try? JSONEncoder().encode(months) else { return }
        ensureCloudDocsDir()
        lastSelfWriteAt = Date()
        coordinatedWrite(data: encoded, to: fileURL)
    }

    /// Overwrites the entire monthly file with the given dictionary.
    /// Used by the debounced save path and the bulk-clear path so we don't
    /// have to enumerate keys. Also overwrites local storage to keep the
    /// two in sync.
    ///
    /// The iCloud write hops off the main thread for the same reason as
    /// `saveState(_:)`.
    func saveAllMonths(_ months: [String: MonthData]) async {
        LocalStorageManager.shared.saveAllMonths(months)

        guard let fileURL = cloudMonthlyURL else { return }
        guard let encoded = try? JSONEncoder().encode(months) else { return }
        ensureCloudDocsDir()
        lastSelfWriteAt = Date()
        await Self.coordinatedWriteOffMain(data: encoded, to: fileURL)
    }

    // MARK: - Migration (Local → iCloud)

    /// Result of a `migrateLocalToCloudIfNeeded` call.
    enum MigrationResult {
        /// iCloud is unavailable on this device — nothing to do.
        case cloudUnavailable
        /// iCloud already has a state file; migration was unnecessary.
        case alreadyMigrated
        /// No meaningful local data to migrate (fresh install).
        case nothingToMigrate
        /// Migration completed successfully.
        case migrated
        /// Local data exists but couldn't be read — left in place for
        /// recovery. The user should be informed so they know their data
        /// hasn't synced to iCloud.
        case localCorrupt
    }

    /// Copies existing local data into iCloud if the cloud container is empty.
    ///
    /// Should be called once at app launch, before loading data. Only migrates
    /// if there's meaningful local data (non-empty people array) and iCloud
    /// doesn't already have a state file. Returns a result code so the caller
    /// can surface a message in the corrupt-local case.
    @discardableResult
    func migrateLocalToCloudIfNeeded() -> MigrationResult {
        guard let stateURL = cloudStateURL else { return .cloudUnavailable }

        // Only migrate if iCloud doesn't already have a state file
        if FileManager.default.fileExists(atPath: stateURL.path) { return .alreadyMigrated }

        let localState: AppState
        do {
            localState = try LocalStorageManager.shared.loadState()
        } catch {
            return .localCorrupt
        }
        guard !localState.people.isEmpty else { return .nothingToMigrate }

        ensureCloudDocsDir()

        lastSelfWriteAt = Date()
        if let data = try? JSONEncoder().encode(localState) {
            coordinatedWrite(data: data, to: stateURL)
        }

        let months = (try? LocalStorageManager.shared.loadMonths()) ?? [:]
        if !months.isEmpty, let monthlyURL = cloudMonthlyURL,
           let data = try? JSONEncoder().encode(months) {
            coordinatedWrite(data: data, to: monthlyURL)
        }
        return .migrated
    }

    // MARK: - NSFileCoordinator Helpers

    /// Reads file data using `NSFileCoordinator` for safe iCloud access.
    private func coordinatedRead(at url: URL) -> Data? {
        var data: Data?
        var error: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordURL in
            data = try? Data(contentsOf: coordURL)
        }
        return data
    }

    /// Writes data to a file using `NSFileCoordinator` for safe iCloud access.
    private func coordinatedWrite(data: Data, to url: URL) {
        var error: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            try? data.write(to: coordURL)
        }
    }

    /// Async wrapper around `coordinatedWrite` that runs the coordinator on
    /// a background task. `NSFileCoordinator` is thread-safe and is meant
    /// to be invoked off the main thread — Apple's own docs warn against
    /// blocking the main thread on ubiquity-tracked file coordination.
    private static func coordinatedWriteOffMain(data: Data, to url: URL) async {
        await Task.detached(priority: .utility) {
            var error: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
                try? data.write(to: coordURL)
            }
        }.value
    }

    /// Creates the Documents directory inside the iCloud container if needed.
    private func ensureCloudDocsDir() {
        guard let docsURL = cloudDocsURL else { return }
        try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
    }

    /// Asks iCloud to download a file if it's not yet available locally.
    private func triggerDownloadIfNeeded(_ url: URL) {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - NSMetadataQuery (iCloud Change Monitoring)

    /// Starts an `NSMetadataQuery` that watches for `.json` file updates
    /// in the iCloud ubiquitous documents scope.
    private func startMonitoring() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        // NSMetadataQuery must be started on the main thread
        DispatchQueue.main.async {
            query.start()
        }
        self.metadataQuery = query
    }

    /// Handles metadata query updates by checking if our files changed.
    @objc private func queryDidUpdate(_ notification: Notification) {
        guard let query = metadataQuery else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        // Suppress the feedback loop: every iCloud write we issue eventually
        // echoes back through this query. Without this guard, every
        // debounced save during editing triggers a `reloadFromCloud()`
        // (two coordinated reads + full state compare) for a change we
        // already have in memory.
        if Date().timeIntervalSince(lastSelfWriteAt) < selfWriteSuppressionWindow {
            return
        }

        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String else { continue }
            if name == stateFilename || name == monthlyFilename {
                NotificationCenter.default.post(name: Self.filesDidChangeExternally, object: nil)
                return
            }
        }
    }
}
