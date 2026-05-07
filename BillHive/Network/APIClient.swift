import Foundation

// MARK: - API Error

/// Errors that can occur during server communication.
enum APIError: LocalizedError {
    /// No server URL has been configured in Settings.
    case noServerURL
    /// The configured server URL could not be parsed.
    case invalidURL
    /// The server returned a non-2xx HTTP status code.
    case httpError(Int, String)
    /// The response data could not be decoded into the expected type.
    case decodingError(Error)
    /// A network-level error occurred (timeout, DNS failure, etc.).
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noServerURL: return "No server URL configured. Go to Settings to set it up."
        case .invalidURL: return "Invalid server URL."
        case .httpError(let code, let msg): return "Server error \(code): \(msg)"
        case .decodingError(let e): return "Data error: \(e.localizedDescription)"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}

// MARK: - Server Kind

/// Identifies which configured server a request should target. The client
/// stores up to two URLs (primary + optional backup) so users can reach
/// their server via different networks (e.g. LAN IP at home, Tailscale IP
/// when remote). Failover is automatic for connection-level failures.
enum ServerKind: String, Codable {
    case primary
    case backup
}

// MARK: - Connection Test Result

/// Returned from `APIClient.testConnection`. Provides the server's reported
/// auth state in addition to the basic success/message tuple, so the UI can
/// distinguish "server reachable but requires a key" from "server reachable,
/// no key needed" and prompt the user accordingly.
struct ConnectionTestResult {
    /// True when /api/health returned 200 AND, if the server requires keys,
    /// our request authenticated successfully.
    let success: Bool
    /// User-facing message for display in the setup UI.
    let message: String
    /// Whether the server has the "Require API key for iOS apps" toggle on.
    /// When `true` and the test was made without a key, the UI should prompt
    /// the user to enter one.
    let requiresKey: Bool
}

// MARK: - API Client

/// Singleton HTTP client for communicating with the SelfHive server.
///
/// All methods are `@MainActor` because the client holds `@Published` state
/// (server URL, reachability) that drives UI updates. Network calls themselves
/// use `URLSession.shared.data(for:)` which suspends off the main thread.
///
/// Supports an optional backup server URL — useful when the same server is
/// reachable at multiple addresses (e.g. `192.168.1.x` on LAN, `100.x.y.z`
/// over Tailscale). Each request first tries the last-known-good server,
/// falling back to the other on connection failure (timeout, DNS, refused).
/// HTTP 4xx/5xx responses are NOT considered failover triggers — the server
/// is reachable, it just rejected the request.
@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    /// Primary server URL string, persisted in UserDefaults.
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }

    /// Optional backup server URL string, persisted in UserDefaults.
    /// Empty string means no backup is configured.
    @Published var backupServerURL: String {
        didSet { UserDefaults.standard.set(backupServerURL, forKey: "backupServerURL") }
    }

    /// Whether the server responded successfully to the last health check.
    @Published var isReachable: Bool = false

    /// Which server was used for the most recent successful request.
    /// Persisted across launches so a returning user picks up where they
    /// left off (e.g. away from home → backup is tried first next launch).
    @Published private(set) var activeServer: ServerKind {
        didSet { UserDefaults.standard.set(activeServer.rawValue, forKey: "activeServer") }
    }

    /// Whether a backup URL has been configured and is non-empty.
    var hasBackup: Bool {
        !backupServerURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Per-device API key (Bearer token). Stored in Keychain, not UserDefaults,
    /// so it isn't backed up to iCloud/iTunes and isn't readable by other apps.
    /// Setting an empty string deletes the persisted key.
    @Published var apiKey: String {
        didSet {
            KeychainHelper.saveApiKey(apiKey)
        }
    }

    /// First 12 chars of the stored key (e.g. "bh_live_a8f3"), or empty if none.
    /// Useful for displaying "configured" state without exposing the full key.
    var apiKeyPrefix: String {
        String(apiKey.prefix(12))
    }

    /// Whether an API key is configured.
    var hasApiKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private init() {
        self.serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        self.backupServerURL = UserDefaults.standard.string(forKey: "backupServerURL") ?? ""
        let stored = UserDefaults.standard.string(forKey: "activeServer") ?? "primary"
        self.activeServer = ServerKind(rawValue: stored) ?? .primary
        self.apiKey = KeychainHelper.loadApiKey() ?? ""
    }

    // MARK: - URL Building

    /// Returns a parsed base URL for the given server kind, or nil if that
    /// server isn't configured.
    private func baseURL(for kind: ServerKind) -> URL? {
        let raw = (kind == .primary) ? serverURL : backupServerURL
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = APIClient.defaultScheme(forHost: s) + "://" + s
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: s)
    }

    /// Picks a default scheme when the user types a bare host. Returns `http`
    /// for hosts that look like RFC 1918 / Tailscale CGNAT / link-local /
    /// .local Bonjour / loopback (where TLS is rarely available), otherwise
    /// `https` so we never silently downgrade traffic to a public host.
    static func defaultScheme(forHost input: String) -> String {
        // Strip optional port; we only care about the host portion.
        let hostPart = input.split(separator: "/").first.map(String.init) ?? input
        let host = hostPart.split(separator: ":").first.map(String.init)?.lowercased() ?? hostPart.lowercased()
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return "http" }
        if host.hasSuffix(".local") { return "http" }
        // IPv4 dotted-quad check + private/CGNAT range detection.
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) {
            let a = parts[0], b = parts[1]
            if a == 10 { return "http" }                                // 10.0.0.0/8
            if a == 192 && b == 168 { return "http" }                   // 192.168.0.0/16
            if a == 172 && (16...31).contains(b) { return "http" }      // 172.16.0.0/12
            if a == 169 && b == 254 { return "http" }                   // 169.254.0.0/16
            if a == 100 && (64...127).contains(b) { return "http" }     // 100.64.0.0/10 (Tailscale CGNAT)
            if a == 127 { return "http" }                               // loopback
        }
        return "https"
    }

    /// Builds a full request URL by appending `path` to the given server's
    /// base URL.
    private func fullURL(_ path: String, kind: ServerKind) -> URL? {
        guard let base = baseURL(for: kind) else { return nil }
        return URL(string: base.absoluteString + path)
    }

    /// True if the given error is a connection-level failure that warrants
    /// trying the alternate server. HTTP 4xx/5xx responses are excluded —
    /// the server is reachable, it just refused the request.
    private func isConnectionFailure(_ error: Error) -> Bool {
        let nse = error as NSError
        guard nse.domain == NSURLErrorDomain else { return false }
        let failoverCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorDNSLookupFailed,
            NSURLErrorResourceUnavailable,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed
        ]
        return failoverCodes.contains(nse.code)
    }

    // MARK: - Request Execution

    /// Executes an HTTP request against a single resolved URL.
    private func performRequest(_ url: URL,
                                method: String,
                                body: Encodable?,
                                rawBody: Data? = nil,
                                contentType: String = "application/json",
                                timeout: TimeInterval = 15) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let rawBody {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = rawBody
        } else if let body {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        // Per-device API key. The server validates it via SHA-256 lookup; an
        // invalid Bearer (e.g. revoked key) gets a 401 from the server's
        // resolveAuth middleware before any handler runs.
        if hasApiKey {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(http.statusCode, msg)
        }
        return data
    }

    /// Sends a request with automatic failover between primary and backup
    /// servers. Tries the last-known-good server first; on connection
    /// failure, retries against the other (if configured). HTTP errors
    /// (4xx/5xx) are surfaced immediately without retry — the server is
    /// up but rejected the request.
    private func request(path: String,
                         method: String = "GET",
                         body: Encodable? = nil,
                         rawBody: Data? = nil,
                         contentType: String = "application/json",
                         timeout: TimeInterval = 15) async throws -> Data {
        // Determine which server to try first based on what last worked
        let order: [ServerKind] = (activeServer == .backup && hasBackup)
            ? [.backup, .primary]
            : [.primary, .backup]

        var firstError: Error?
        for kind in order {
            guard let url = fullURL(path, kind: kind) else { continue }
            do {
                let data = try await performRequest(url,
                                                    method: method,
                                                    body: body,
                                                    rawBody: rawBody,
                                                    contentType: contentType,
                                                    timeout: timeout)
                if activeServer != kind {
                    activeServer = kind
                }
                return data
            } catch let e as APIError {
                // HTTP 4xx/5xx — server is reachable, don't fall over
                if case .httpError = e { throw e }
                if firstError == nil { firstError = e }
            } catch {
                if firstError == nil { firstError = error }
                if !isConnectionFailure(error) {
                    // Non-network error we don't know how to retry past
                    throw APIError.networkError(error)
                }
                // Connection failure — try next configured server
            }
        }

        // No URLs configured at all
        if firstError == nil { throw APIError.noServerURL }
        if let e = firstError as? APIError { throw e }
        throw APIError.networkError(firstError!)
    }

    /// Decodes raw data into the specified `Decodable` type.
    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Health

    /// Pings the active server's `/api/health` endpoint. Failover applies —
    /// if both primary and backup are configured, this returns true if
    /// either responds.
    func health() async throws -> Bool {
        let data = try await request(path: "/api/health")
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["ok"] as? Bool == true
    }

    /// Concurrently pings both primary and backup servers with a short timeout
    /// and switches `activeServer` to whichever responds first.
    ///
    /// Call on app launch and foreground return to detect network changes
    /// (e.g. switching from home Wi-Fi to cellular/VPN) without making the
    /// user wait for a 15-second timeout on the stale server.
    ///
    /// When only one server is configured, this is a simple health ping.
    /// Returns `true` if at least one server responded.
    func probeServers() async -> Bool {
        let probeTimeout: TimeInterval = 4

        guard !serverURL.isEmpty else { return false }

        // Single server — just ping it
        guard hasBackup else {
            guard let url = fullURL("/api/health", kind: .primary) else { return false }
            do {
                let data = try await performRequest(url, method: "GET", body: Optional<String>.none, timeout: probeTimeout)
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let ok = obj?["ok"] as? Bool == true
                if ok { isReachable = true }
                return ok
            } catch {
                isReachable = false
                return false
            }
        }

        // Two servers — race them concurrently, pick the winner
        let primaryURL = fullURL("/api/health", kind: .primary)
        let backupURL  = fullURL("/api/health", kind: .backup)

        // Use a task group to race both pings; first success wins.
        let winner: ServerKind? = await withTaskGroup(of: ServerKind?.self) { group in
            if let url = primaryURL {
                group.addTask { [self] in
                    do {
                        let data = try await self.performRequest(url, method: "GET", body: Optional<String>.none, timeout: probeTimeout)
                        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        return (obj?["ok"] as? Bool == true) ? .primary : nil
                    } catch { return nil }
                }
            }
            if let url = backupURL {
                group.addTask { [self] in
                    do {
                        let data = try await self.performRequest(url, method: "GET", body: Optional<String>.none, timeout: probeTimeout)
                        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        return (obj?["ok"] as? Bool == true) ? .backup : nil
                    } catch { return nil }
                }
            }

            // Return the first non-nil result (the faster server)
            for await result in group {
                if let kind = result {
                    group.cancelAll()
                    return kind
                }
            }
            return nil
        }

        if let winner {
            if activeServer != winner { activeServer = winner }
            isReachable = true
            return true
        }

        isReachable = false
        return false
    }

    /// Pings a specific URL (not from configured state) — used during
    /// onboarding to test a candidate URL before saving it.
    ///
    /// If `apiKey` is non-empty, it's sent as `Authorization: Bearer` so the
    /// user can verify their key works. The server's /api/health endpoint
    /// reports `requireDeviceKeys` and `authMethod`; we use those to give
    /// nuanced feedback ("server requires a key", "connected as marty", etc.).
    static func testConnection(rawURL: String,
                               apiKey: String = "",
                               timeout: TimeInterval = 10) async -> ConnectionTestResult {
        var s = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else {
            return ConnectionTestResult(success: false, message: "URL is empty", requiresKey: false)
        }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = APIClient.defaultScheme(forHost: s) + "://" + s
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: s + "/api/health") else {
            return ConnectionTestResult(success: false, message: "Invalid URL", requiresKey: false)
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 {
                    return ConnectionTestResult(
                        success: false,
                        message: "Authentication failed. Check your API key.",
                        requiresKey: true
                    )
                }
                if !(200..<300).contains(http.statusCode) {
                    return ConnectionTestResult(
                        success: false,
                        message: "Server error \(http.statusCode)",
                        requiresKey: false
                    )
                }
            }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let ok           = obj?["ok"] as? Bool == true
            let requiresKey  = obj?["requireDeviceKeys"] as? Bool == true
            let authMethod   = obj?["authMethod"] as? String ?? "fallback"
            let resolvedUser = obj?["user"] as? String ?? "local"

            guard ok else {
                return ConnectionTestResult(
                    success: false,
                    message: "Server responded but health check failed",
                    requiresKey: requiresKey
                )
            }
            // Authenticated via Bearer — strongest signal.
            if authMethod == "bearer" {
                return ConnectionTestResult(
                    success: true,
                    message: "Connected as \(resolvedUser)",
                    requiresKey: requiresKey
                )
            }
            // Server requires keys but we didn't provide one (or the proxy
            // header-based path got us in for /api/health). Tell the user.
            if requiresKey && trimmedKey.isEmpty {
                return ConnectionTestResult(
                    success: false,
                    message: "This server requires an API key. Add one below to connect.",
                    requiresKey: true
                )
            }
            return ConnectionTestResult(
                success: true,
                message: "Connection successful!",
                requiresKey: requiresKey
            )
        } catch {
            return ConnectionTestResult(
                success: false,
                message: error.localizedDescription,
                requiresKey: false
            )
        }
    }

    // MARK: - State (CRUD)

    /// Fetches the complete app state from the server.
    ///
    /// Attempts strict `Codable` decoding first. If that fails (e.g. the
    /// server returns a slightly different schema), falls back to flexible
    /// per-key parsing to maximize forward compatibility.
    func getState() async throws -> AppState {
        let data = try await request(path: "/api/state")
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            // Flexible fallback: parse each top-level key independently
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw APIError.decodingError(error)
            }
            var state = AppState()
            if let settingsData = try? JSONSerialization.data(withJSONObject: dict["settings"] ?? [:]) {
                state.settings = (try? JSONDecoder().decode(AppSettings.self, from: settingsData)) ?? AppSettings()
            }
            if let peopleData = try? JSONSerialization.data(withJSONObject: dict["people"] ?? []) {
                state.people = (try? JSONDecoder().decode([Person].self, from: peopleData)) ?? []
            }
            if let billsData = try? JSONSerialization.data(withJSONObject: dict["bills"] ?? []) {
                state.bills = (try? JSONDecoder().decode([Bill].self, from: billsData)) ?? []
            }
            if let clData = try? JSONSerialization.data(withJSONObject: dict["checklist"] ?? [:]) {
                state.checklist = (try? JSONDecoder().decode([String: [String: Bool]].self, from: clData)) ?? [:]
            }
            return state
        }
    }

    /// Saves the complete app state to the server via PUT.
    func saveState(_ state: AppState) async throws {
        _ = try await request(path: "/api/state", method: "PUT", body: AnyEncodable(state))
    }

    /// Patches a single top-level key in the server state (e.g. "people", "bills").
    func patchState(key: String, value: Encodable) async throws {
        _ = try await request(path: "/api/state/\(key)", method: "PATCH", body: AnyEncodable(value))
    }

    // MARK: - Monthly Data

    /// Fetches all months' data from the server.
    func getAllMonths() async throws -> [String: MonthData] {
        let data = try await request(path: "/api/months")
        return (try? JSONDecoder().decode([String: MonthData].self, from: data)) ?? [:]
    }

    /// Fetches a single month's data from the server.
    func getMonth(_ key: String) async throws -> MonthData {
        let data = try await request(path: "/api/months/\(key)")
        return (try? JSONDecoder().decode(MonthData.self, from: data)) ?? MonthData()
    }

    /// Saves a single month's data to the server via PUT.
    func saveMonth(_ key: String, data: MonthData) async throws {
        _ = try await request(path: "/api/months/\(key)", method: "PUT", body: data)
    }

    /// Deletes a month's data from the server.
    func deleteMonth(_ key: String) async throws {
        _ = try await request(path: "/api/months/\(key)", method: "DELETE")
    }

    // MARK: - Email Config

    /// Fetches the server-side email relay configuration.
    func getEmailConfig() async throws -> EmailConfig? {
        let data = try await request(path: "/api/email/config")
        if data == Data("null".utf8) { return nil }
        return try? JSONDecoder().decode(EmailConfig.self, from: data)
    }

    /// Saves the email relay configuration to the server.
    func saveEmailConfig(_ config: EmailConfig) async throws {
        _ = try await request(path: "/api/email/config", method: "PUT", body: config)
    }

    /// Triggers a test email via the server's configured relay.
    func testEmail() async throws -> String {
        let data = try await request(path: "/api/email/test", method: "POST")
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["message"] as? String ?? "Test email sent"
    }

    /// Sends a bill summary email to a person via the server's email relay.
    ///
    /// The server generates the HTML template and dispatches via the configured
    /// provider. Body is encoded manually because `bills` contains heterogeneous
    /// types (`[String: Any]`); we route through `request(path:rawBody:)` so
    /// failover still applies.
    func sendEmail(to: String, greeting: String, personName: String, accentColor: String,
                   monthLabel: String, bills: [[String: Any]], total: Double,
                   payMethod: String, payId: String, zelleUrl: String?) async throws {
        var body: [String: Any] = [
            "to": to,
            "greeting": greeting,
            "personName": personName,
            "accentColor": accentColor,
            "monthLabel": monthLabel,
            "bills": bills,
            "total": total,
            "payMethod": payMethod,
            "payId": payId
        ]
        if let zu = zelleUrl { body["zelleUrl"] = zu }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await request(path: "/api/email/send", method: "POST", rawBody: bodyData)
    }

    // MARK: - Export / Import

    /// Returns the URL for downloading a full data export from the active
    /// server. Uses whichever server most recently worked.
    func exportURL() -> URL? {
        let preferred: ServerKind = (activeServer == .backup && hasBackup) ? .backup : .primary
        return fullURL("/api/export", kind: preferred) ?? fullURL("/api/export", kind: .primary)
    }

    /// Imports a backup JSON file to the server, replacing all data.
    func importBackup(_ data: Data) async throws {
        _ = try await request(path: "/api/import", method: "POST", rawBody: data, timeout: 30)
    }
}

// MARK: - AnyEncodable

/// Type-erased wrapper that allows encoding any `Encodable` value as a request body.
///
/// Used by `APIClient.request(_:method:body:)` to accept heterogeneous encodable
/// types without requiring a generic parameter on the request method.
struct AnyEncodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    init<T: Encodable & Sendable>(_ value: T) {
        _encode = { encoder in try value.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
