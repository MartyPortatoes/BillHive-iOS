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

// MARK: - API Client

/// Singleton HTTP client for communicating with the SelfHive server.
///
/// All methods are `@MainActor` because the client holds `@Published` state
/// (server URL, reachability) that drives UI updates. Network calls themselves
/// use `URLSession.shared.data(for:)` which suspends off the main thread.
///
/// The server URL is persisted in `UserDefaults` and configurable from Settings.
@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    /// The server URL string, persisted in UserDefaults.
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }

    /// Whether the server responded successfully to the last health check.
    @Published var isReachable: Bool = false

    /// Parsed base URL, with protocol defaulting to `http://` and trailing slashes stripped.
    private var baseURL: URL? {
        guard !serverURL.isEmpty else { return nil }
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http") { s = "http://" + s }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: s)
    }

    private init() {
        self.serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    }

    // MARK: - URL Building

    /// Constructs a full URL by appending `path` to the base URL.
    ///
    /// - Throws: `APIError.noServerURL` if no server is configured,
    ///   or `APIError.invalidURL` if the result isn't a valid URL.
    private func url(_ path: String) throws -> URL {
        guard let base = baseURL else { throw APIError.noServerURL }
        guard let url = URL(string: base.absoluteString + path) else { throw APIError.invalidURL }
        return url
    }

    // MARK: - Request Execution

    /// Executes an HTTP request and returns the raw response data.
    ///
    /// Automatically encodes the `body` as JSON if provided. Throws typed
    /// `APIError` variants for HTTP errors and network failures.
    private func request(_ url: URL, method: String = "GET", body: Encodable? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        req.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.httpError(http.statusCode, msg)
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.networkError(error)
        }
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

    /// Pings the server's `/api/health` endpoint to verify connectivity.
    func health() async throws -> Bool {
        let data = try await request(try url("/api/health"))
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["ok"] as? Bool == true
    }

    // MARK: - State (CRUD)

    /// Fetches the complete app state from the server.
    ///
    /// Attempts strict `Codable` decoding first. If that fails (e.g. the
    /// server returns a slightly different schema), falls back to flexible
    /// per-key parsing to maximize forward compatibility.
    func getState() async throws -> AppState {
        let data = try await request(try url("/api/state"))
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
        _ = try await request(try url("/api/state"), method: "PUT", body: AnyEncodable(state))
    }

    /// Patches a single top-level key in the server state (e.g. "people", "bills").
    func patchState(key: String, value: Encodable) async throws {
        _ = try await request(try url("/api/state/\(key)"), method: "PATCH", body: AnyEncodable(value))
    }

    // MARK: - Monthly Data

    /// Fetches all months' data from the server.
    func getAllMonths() async throws -> [String: MonthData] {
        let data = try await request(try url("/api/months"))
        return (try? JSONDecoder().decode([String: MonthData].self, from: data)) ?? [:]
    }

    /// Fetches a single month's data from the server.
    func getMonth(_ key: String) async throws -> MonthData {
        let data = try await request(try url("/api/months/\(key)"))
        return (try? JSONDecoder().decode(MonthData.self, from: data)) ?? MonthData()
    }

    /// Saves a single month's data to the server via PUT.
    func saveMonth(_ key: String, data: MonthData) async throws {
        _ = try await request(try url("/api/months/\(key)"), method: "PUT", body: data)
    }

    /// Deletes a month's data from the server.
    func deleteMonth(_ key: String) async throws {
        _ = try await request(try url("/api/months/\(key)"), method: "DELETE")
    }

    // MARK: - Email Config

    /// Fetches the server-side email relay configuration.
    func getEmailConfig() async throws -> EmailConfig? {
        let data = try await request(try url("/api/email/config"))
        if data == Data("null".utf8) { return nil }
        return try? JSONDecoder().decode(EmailConfig.self, from: data)
    }

    /// Saves the email relay configuration to the server.
    func saveEmailConfig(_ config: EmailConfig) async throws {
        _ = try await request(try url("/api/email/config"), method: "PUT", body: config)
    }

    /// Triggers a test email via the server's configured relay.
    func testEmail() async throws -> String {
        let data = try await request(try url("/api/email/test"), method: "POST")
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["message"] as? String ?? "Test email sent"
    }

    /// Sends a bill summary email to a person via the server's email relay.
    ///
    /// The server generates the HTML template and dispatches via the configured
    /// provider. This method manually builds the JSON payload because the
    /// `bills` array contains mixed types (`[String: Any]`).
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
        var req = URLRequest(url: try url("/api/email/send"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Export / Import

    /// Returns the URL for downloading a full data export from the server.
    func exportURL() -> URL? {
        guard let base = baseURL else { return nil }
        return URL(string: base.absoluteString + "/api/export")
    }

    /// Imports a backup JSON file to the server, replacing all data.
    func importBackup(_ data: Data) async throws {
        var req = URLRequest(url: try url("/api/import"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 30
        _ = try await URLSession.shared.data(for: req)
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
        _encode = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
