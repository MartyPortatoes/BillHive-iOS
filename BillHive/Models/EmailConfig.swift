import Foundation

enum EmailProvider: String, Codable, CaseIterable {
    case disabled = ""
    case smtp = "smtp"
    case mailgun = "mailgun"
    case sendgrid = "sendgrid"
    case resend = "resend"

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

struct EmailConfig: Codable {
    var provider: String
    var fromName: String
    var fromEmail: String

    // SMTP
    var smtpHost: String?
    var smtpPort: String?
    var smtpUser: String?
    var smtpPass: String?
    var smtpSecure: Bool?

    // Mailgun
    var mailgunApiKey: String?
    var mailgunDomain: String?
    var mailgunRegion: String?

    // SendGrid
    var sendgridApiKey: String?

    // Resend
    var resendApiKey: String?

    init() {
        self.provider = ""
        self.fromName = ""
        self.fromEmail = ""
    }

    var emailProvider: EmailProvider {
        EmailProvider(rawValue: provider) ?? .disabled
    }

    func isMasked(_ value: String?) -> Bool {
        value?.contains("••••") == true
    }
}
