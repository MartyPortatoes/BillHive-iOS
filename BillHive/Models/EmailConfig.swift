import Foundation

// MARK: - Email Provider

/// Supported email relay providers for sending HTML bill summaries.
///
/// The server-side relay accepts a provider selection plus the relevant
/// credentials and handles the actual SMTP/API dispatch.
enum EmailProvider: String, Codable, CaseIterable, Sendable {
    case disabled = ""
    case smtp = "smtp"
    case mailgun = "mailgun"
    case sendgrid = "sendgrid"
    case resend = "resend"

    /// Human-readable label for display in the provider picker.
    var displayName: String {
        switch self {
        case .disabled: return "— Disabled —"
        case .smtp: return "SMTP"
        case .mailgun: return "Mailgun"
        case .sendgrid: return "SendGrid"
        case .resend: return "Resend"
        }
    }
}

// MARK: - Email Config

/// Server-side email relay configuration.
///
/// Stored on the server via `/api/email/config`. API keys and passwords are
/// masked with "••••" when retrieved — the `isMasked(_:)` helper detects
/// whether a field still holds the server's masked placeholder.
struct EmailConfig: Codable, Sendable {
    /// The raw provider string (maps to `EmailProvider`).
    var provider: String
    /// "From" display name in outgoing emails.
    var fromName: String
    /// "From" email address in outgoing emails.
    var fromEmail: String

    // MARK: SMTP Fields

    var smtpHost: String?
    var smtpPort: String?
    var smtpUser: String?
    var smtpPass: String?
    var smtpSecure: Bool?

    // MARK: Mailgun Fields

    var mailgunApiKey: String?
    var mailgunDomain: String?
    var mailgunRegion: String?

    // MARK: SendGrid Fields

    var sendgridApiKey: String?

    // MARK: Resend Fields

    var resendApiKey: String?

    init() {
        self.provider = ""
        self.fromName = ""
        self.fromEmail = ""
    }

    /// The typed `EmailProvider` enum derived from the raw `provider` string.
    var emailProvider: EmailProvider {
        EmailProvider(rawValue: provider) ?? .disabled
    }

    /// Returns `true` if the value contains the server's mask placeholder ("••••"),
    /// indicating it hasn't been edited by the user since being fetched.
    func isMasked(_ value: String?) -> Bool {
        value?.contains("••••") == true
    }
}
