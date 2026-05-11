import Foundation
import SwiftUI

// MARK: - Payment Method

/// Supported payment methods for collecting money from household members.
///
/// Each method determines what fields are relevant in the person's settings
/// (e.g. Venmo needs a handle, Zelle needs a phone/email) and what deep-link
/// URL is generated on the Send & Receive screen.
enum PayMethod: String, Codable, CaseIterable, Sendable {
    case none = "none"
    case zelle = "zelle"
    case venmo = "venmo"
    case cashapp = "cashapp"
    case manual = "manual"

    /// Human-readable label for display in pickers.
    var displayName: String {
        switch self {
        case .none: return "None"
        case .zelle: return "Zelle"
        case .venmo: return "Venmo"
        case .cashapp: return "Cash App"
        case .manual: return "Manual"
        }
    }
}

// MARK: - Person

/// A household member who participates in bill splitting.
///
/// The first person (id == "me") represents the primary user — the one who
/// fronts all bills and collects from everyone else. This person cannot be
/// removed and is always present in the people array.
struct Person: Identifiable, Codable, Equatable, Sendable {
    var id: String
    /// Display name shown throughout the app.
    var name: String
    /// Hex color string (e.g. "#F5A800") used as the person's accent color.
    var color: String
    /// How this person prefers to pay or be paid.
    var payMethod: PayMethod
    /// Payment identifier — Venmo handle, Cash App tag, or Zelle phone/email.
    var payId: String
    /// Optional custom Zelle payment URL (overrides the auto-generated one).
    var zelleUrl: String?
    /// Email address for sending bill notifications.
    var email: String
    /// Custom opening line for bill emails (e.g. "Hey roomie,").
    var greeting: String

    /// Whether this person is the primary "me" user.
    var isMe: Bool { id == "me" }

    /// SwiftUI `Color` derived from the hex string.
    var swiftUIColor: Color {
        Color(hex: color) ?? .orange
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, color, payMethod, payId, zelleUrl, email, greeting
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(String.self, forKey: .color)
        payMethod = try c.decode(PayMethod.self, forKey: .payMethod)
        payId = try c.decode(String.self, forKey: .payId)
        zelleUrl = try c.decodeIfPresent(String.self, forKey: .zelleUrl)
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        greeting = try c.decodeIfPresent(String.self, forKey: .greeting) ?? ""
    }

    // MARK: - Init

    init(
        id: String = "p\(Int(Date().timeIntervalSince1970 * 1000))",
        name: String = "New Person",
        color: String = "#5bc4f5",
        payMethod: PayMethod = .manual,
        payId: String = "",
        zelleUrl: String? = nil,
        email: String = "",
        greeting: String = ""
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.payMethod = payMethod
        self.payId = payId
        self.zelleUrl = zelleUrl
        self.email = email
        self.greeting = greeting
    }

    // MARK: - Color Palette

    /// Rotating color palette assigned to new people in order.
    static let personColors = [
        "#F5A800", "#5bc4f5", "#f5a623", "#f06292",
        "#b39ddb", "#ef5350", "#ffd54f", "#a5d6a7"
    ]
}

// MARK: - Color Hex Extension

extension Color {
    /// Creates a `Color` from a hex string (e.g. "#FF8800" or "FF880080").
    ///
    /// Supports 6-digit (RGB) and 8-digit (ARGB) hex strings.
    /// Returns `nil` if the string is not a valid hex color.
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Converts a SwiftUI `Color` to a hex string (e.g. "#FF8800").
    ///
    /// Uses `UIColor` for component extraction. Returns `nil` if the color
    /// space conversion fails.
    func toHex() -> String? {
        let uic = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uic.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
