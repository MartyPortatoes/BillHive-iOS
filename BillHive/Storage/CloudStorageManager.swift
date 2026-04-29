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

    /// Loads the app state from iCloud, falling back to local storage if unavailable.
    func loadState() -> AppState {
        guard let fileURL = cloudStateURL else {
            return LocalStorageManager.shared.loadState()
        }
        triggerDownloadIfNeeded(fileURL)
        guard let data = coordinatedRead(at: fileURL),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else {
            return LocalStorageManager.shared.loadState()
        }
        return state
    }

    /// Saves the app state to both iCloud and local storage (backup).
    func saveState(_ state: AppState) {
        // Always keep a local copy as backup in case iCloud becomes unavailable
        LocalStorageManager.shared.saveState(state)

        guard let fileURL = cloudStateURL else { return }
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        ensureCloudDocsDir()
        coordinatedWrite(data: encoded, to: fileURL)
    }

    /// Loads all monthly data from iCloud, falling back to local storage if unavailable.
    func loadMonths() -> [String: MonthData] {
        guard let fileURL = cloudMonthlyURL else {
            return LocalStorageManager.shared.loadMonths()
        }
        triggerDownloadIfNeeded(fileURL)
        guard let data = coordinatedRead(at: fileURL),
              let months = try? JSONDecoder().decode([String: MonthData].self, from: data) else {
            return LocalStorageManager.shared.loadMonths()
        }
        return months
    }

    /// Saves a single month's data, merging it into the existing monthly file.
    ///
    /// Reads the current months from iCloud, updates the entry for `key`,
    /// and rewrites the file. Also saves to local storage as backup.
    func saveMonth(_ key: String, data: MonthData) {
        LocalStorageManager.shared.saveMonth(key, data: data)

        guard let fileURL = cloudMonthlyURL else { return }
        var months = loadMonths()
        months[key] = data
        guard let encoded = try? JSONEncoder().encode(months) else { return }
        ensureCloudDocsDir()
        coordinatedWrite(data: encoded, to: fileURL)
    }

    /// Overwrites the entire monthly file with the given dictionary.
    /// Used by the bulk-clear path so we don't have to enumerate keys.
    /// Also overwrites local storage to keep the two in sync.
    func saveAllMonths(_ months: [String: MonthData]) {
        LocalStorageManager.shared.saveAllMonths(months)

        guard let fileURL = cloudMonthlyURL else { return }
        guard let encoded = try? JSONEncoder().encode(months) else { return }
        ensureCloudDocsDir()
        coordinatedWrite(data: encoded, to: fileURL)
    }

    // MARK: - Migration (Local → iCloud)

    /// Copies existing local data into iCloud if the cloud container is empty.
    ///
    /// Should be called once at app launch, before loading data. Only migrates
    /// if there's meaningful local data (non-empty people array) and iCloud
    /// doesn't already have a state file.
    func migrateLocalToCloudIfNeeded() {
        guard let stateURL = cloudStateURL else { return }

        // Only migrate if iCloud doesn't already have a state file
        if FileManager.default.fileExists(atPath: stateURL.path) { return }

        let localState = LocalStorageManager.shared.loadState()
        guard !localState.people.isEmpty else { return }

        ensureCloudDocsDir()

        if let data = try? JSONEncoder().encode(localState) {
            coordinatedWrite(data: data, to: stateURL)
        }

        let months = LocalStorageManager.shared.loadMonths()
        if !months.isEmpty, let monthlyURL = cloudMonthlyURL,
           let data = try? JSONEncoder().encode(months) {
            coordinatedWrite(data: data, to: monthlyURL)
        }
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
