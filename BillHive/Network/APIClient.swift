import Foundation

enum APIError: LocalizedError {
    case noServerURL
    case invalidURL
    case httpError(Int, String)
    case decodingError(Error)
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

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    @Published var isReachable: Bool = false

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

    private func url(_ path: String) throws -> URL {
        guard let base = baseURL else { throw APIError.noServerURL }
        guard let url = URL(string: base.absoluteString + path) else { throw APIError.invalidURL }
        return url
    }

    private func request(_ url: URL, method: String = "GET", body: Encodable? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body = body {
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

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Health

    func health() async throws -> Bool {
        let data = try await request(try url("/api/health"))
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["ok"] as? Bool == true
    }

    // MARK: - State

    func getState() async throws -> AppState {
        let data = try await request(try url("/api/state"))
        // The state is returned as a flat object with keys: settings, people, bills, checklist
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            // Try flexible parsing
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

    func saveState(_ state: AppState) async throws {
        let data = try url("/api/state")
        let body = try JSONEncoder().encode(state)
        var req = URLRequest(url: data)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        _ = try await request(data, method: "PUT", body: AnyEncodable(state))
    }

    func patchState(key: String, value: Encodable) async throws {
        _ = try await request(try url("/api/state/\(key)"), method: "PATCH", body: AnyEncodable(value))
    }

    // MARK: - Monthly Data

    func getAllMonths() async throws -> [String: MonthData] {
        let data = try await request(try url("/api/months"))
        return (try? JSONDecoder().decode([String: MonthData].self, from: data)) ?? [:]
    }

    func getMonth(_ key: String) async throws -> MonthData {
        let data = try await request(try url("/api/months/\(key)"))
        return (try? JSONDecoder().decode(MonthData.self, from: data)) ?? MonthData()
    }

    func saveMonth(_ key: String, data: MonthData) async throws {
        _ = try await request(try url("/api/months/\(key)"), method: "PUT", body: data)
    }

    func deleteMonth(_ key: String) async throws {
        _ = try await request(try url("/api/months/\(key)"), method: "DELETE")
    }

    // MARK: - Email Config

    func getEmailConfig() async throws -> EmailConfig? {
        let data = try await request(try url("/api/email/config"))
        if data == Data("null".utf8) { return nil }
        return try? JSONDecoder().decode(EmailConfig.self, from: data)
    }

    func saveEmailConfig(_ config: EmailConfig) async throws {
        _ = try await request(try url("/api/email/config"), method: "PUT", body: config)
    }

    func testEmail() async throws -> String {
        let data = try await request(try url("/api/email/test"), method: "POST")
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["message"] as? String ?? "Test email sent"
    }

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

    func exportURL() -> URL? {
        guard let base = baseURL else { return nil }
        return URL(string: base.absoluteString + "/api/export")
    }

    func importBackup(_ data: Data) async throws {
        var req = URLRequest(url: try url("/api/import"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 30
        _ = try await URLSession.shared.data(for: req)
    }
}

// Helper for encoding any Encodable as body
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        _encode = value.encode(to:)
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
