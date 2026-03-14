import Foundation

/// Manages iCloud Document storage for BillHive (standalone).
/// Syncs state.json and monthly.json across devices via iCloud Drive.
/// Falls back to LocalStorageManager when iCloud is unavailable.
class CloudStorageManager: NSObject {
    static let shared = CloudStorageManager()

    /// Posted when iCloud delivers updated files from another device.
    static let filesDidChangeExternally = Notification.Name("CloudStorageFilesDidChange")

    private let containerID = "iCloud.com.billhive.app"
    private let stateFilename = "state.json"
    private let monthlyFilename = "monthly.json"

    /// Cached ubiquity container URL. nil = iCloud unavailable → local fallback.
    private var iCloudURL: URL?
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

    /// Whether iCloud storage is active (vs local fallback).
    var isCloudAvailable: Bool { iCloudURL != nil }

    // MARK: - Documents directory inside iCloud container

    private var cloudDocsURL: URL? {
        iCloudURL?.appendingPathComponent("Documents")
    }

    private var cloudStateURL: URL? {
        cloudDocsURL?.appendingPathComponent(stateFilename)
    }

    private var cloudMonthlyURL: URL? {
        cloudDocsURL?.appendingPathComponent(monthlyFilename)
    }

    // MARK: - Public API (same signatures as LocalStorageManager)

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

    func saveState(_ state: AppState) {
        // Always keep local copy as backup
        LocalStorageManager.shared.saveState(state)

        guard let fileURL = cloudStateURL else { return }
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        ensureCloudDocsDir()
        coordinatedWrite(data: encoded, to: fileURL)
    }

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

    func saveMonth(_ key: String, data: MonthData) {
        // Always keep local copy as backup
        LocalStorageManager.shared.saveMonth(key, data: data)

        guard let fileURL = cloudMonthlyURL else { return }
        // Load current months from cloud, merge, rewrite
        var months = loadMonths()
        months[key] = data
        guard let encoded = try? JSONEncoder().encode(months) else { return }
        ensureCloudDocsDir()
        coordinatedWrite(data: encoded, to: fileURL)
    }

    // MARK: - Migration (local → iCloud, one-time)

    /// Copies existing local data into iCloud if the cloud container is empty.
    /// Call once at app launch before loading data.
    func migrateLocalToCloudIfNeeded() {
        guard let stateURL = cloudStateURL else { return }

        // Only migrate if iCloud doesn't already have a state file
        if FileManager.default.fileExists(atPath: stateURL.path) { return }

        let localState = LocalStorageManager.shared.loadState()
        // Only migrate if there's meaningful local data
        guard !localState.people.isEmpty else { return }

        ensureCloudDocsDir()

        // Copy state
        if let data = try? JSONEncoder().encode(localState) {
            coordinatedWrite(data: data, to: stateURL)
        }

        // Copy monthly
        let months = LocalStorageManager.shared.loadMonths()
        if !months.isEmpty, let monthlyURL = cloudMonthlyURL,
           let data = try? JSONEncoder().encode(months) {
            coordinatedWrite(data: data, to: monthlyURL)
        }
    }

    // MARK: - NSFileCoordinator helpers

    private func coordinatedRead(at url: URL) -> Data? {
        var data: Data?
        var error: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordURL in
            data = try? Data(contentsOf: coordURL)
        }
        return data
    }

    private func coordinatedWrite(data: Data, to url: URL) {
        var error: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { coordURL in
            try? data.write(to: coordURL)
        }
    }

    private func ensureCloudDocsDir() {
        guard let docsURL = cloudDocsURL else { return }
        try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
    }

    private func triggerDownloadIfNeeded(_ url: URL) {
        guard FileManager.default.isUbiquitousItem(at: url) else { return }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - NSMetadataQuery (iCloud file change monitoring)

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
