import Foundation
import SwiftUI

enum PayMethod: String, Codable, CaseIterable {
    case none = "none"
    case zelle = "zelle"
    case venmo = "venmo"
    case cashapp = "cashapp"
    case manual = "manual"

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

struct Person: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var color: String
    var payMethod: PayMethod
    var payId: String
    var zelleUrl: String?
    var email: String
    var greeting: String

    var isMe: Bool { id == "me" }

    var swiftUIColor: Color {
        Color(hex: color) ?? .orange
    }

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

    static let personColors = [
        "#F5A800", "#5bc4f5", "#f5a623", "#f06292",
        "#b39ddb", "#ef5350", "#ffd54f", "#a5d6a7"
    ]
}

extension Color {
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
}
