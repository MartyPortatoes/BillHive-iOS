import SwiftUI
import UIKit

// MARK: - Design Tokens (Colors)

/// App-wide color palette. Surface and text tokens adapt to the current
/// color scheme (light vs. dark); brand and status colors stay constant.
///
/// The dark variant matches the BillHive web app's CSS custom properties.
/// The light variant uses warm cream surfaces to complement the amber brand.
extension Color {
    /// Primary background — page-level fill behind everything.
    static let bhBackground = Color.bhDynamic(light: "#faf9f4", dark: "#0c0d0f")
    /// Card / elevated surface.
    static let bhSurface    = Color.bhDynamic(light: "#ffffff", dark: "#141518")
    /// Secondary surface — input backgrounds, segmented controls.
    static let bhSurface2   = Color.bhDynamic(light: "#f3f1ea", dark: "#1c1e22")
    /// Tertiary surface — subtle bill icon tints, hover states.
    static let bhSurface3   = Color.bhDynamic(light: "#e8e6dd", dark: "#242629")
    /// Standard 1pt border.
    static let bhBorder     = Color.bhDynamic(light: "#dad7cc", dark: "#2a2c31")
    /// Emphasized border (active state, selection).
    static let bhBorder2    = Color.bhDynamic(light: "#bfbcaf", dark: "#34373d")
    /// Primary text color.
    static let bhText       = Color.bhDynamic(light: "#0c0d0f", dark: "#e4e5e8")
    /// Muted text — labels, captions.
    static let bhMuted      = Color.bhDynamic(light: "#6f717a", dark: "#767880")
    /// Most muted text — disabled, placeholder.
    static let bhMuted2     = Color.bhDynamic(light: "#a4a7ad", dark: "#4a4c52")

    /// Brand amber — same in both schemes.
    static let bhAmber = Color(hex: "#F5A800") ?? .orange
    /// Info blue — same in both schemes.
    static let bhBlue  = Color(hex: "#5bc4f5") ?? .blue
    /// Error red — same in both schemes.
    static let bhRed   = Color(hex: "#ef5350") ?? .red

    /// Builds a `Color` whose value is resolved at render time based on the
    /// current `UITraitCollection.userInterfaceStyle`. Lets the same token
    /// emit different hex values for light vs. dark.
    static func bhDynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = (traits.userInterfaceStyle == .dark) ? dark : light
            return UIColor(Color(hex: hex) ?? .gray)
        })
    }
}

// MARK: - Design Tokens (Fonts)

/// Semantic font tokens used throughout the app.
///
/// All fonts scale with Dynamic Type. The `.monospacedDigit()` modifier
/// keeps decimal alignment without forcing a full monospaced design on
/// non-numeric text. Use `.monospaced()` only where glyph-grid alignment
/// matters (section labels, code-like text).
extension Font {
    /// Large view header title (e.g. "Bills", "Summary").
    static let bhViewTitle = Font.title3.weight(.bold)
    /// Subtitle under view headers — short description line.
    static let bhSubtitle = Font.footnote
    /// Uppercase section title inside cards.
    static let bhSectionTitle = Font.caption2.weight(.medium).monospaced()
    /// Primary body text — used for tabular/code-like content. Monospaced.
    static let bhBody = Font.subheadline.weight(.semibold).monospaced()
    /// Secondary body text — row content, inputs. Monospaced.
    static let bhBodySecondary = Font.footnote.monospaced()
    /// Proportional name text — bill names, person names, prose labels.
    /// Use this instead of `bhBody` whenever the text is a proper noun or sentence.
    static let bhBodyName = Font.subheadline.weight(.semibold)
    /// Proportional secondary name text — sub-labels, hint copy under titles.
    static let bhBodyNameSecondary = Font.footnote
    /// Small caption / hint text.
    static let bhCaption = Font.caption2.monospaced()
    /// Large monetary amount — hero totals.
    static let bhMoneyLarge = Font.title2.weight(.bold).monospacedDigit()
    /// Medium monetary amount — bill totals.
    static let bhMoneyMedium = Font.title3.weight(.semibold).monospacedDigit()
    /// Small monetary amount — line items.
    static let bhMoneySmall = Font.footnote.weight(.semibold).monospacedDigit()
}

// MARK: - View Modifiers

extension View {
    /// Applies the standard BillHive card style — surface background with a border.
    func bhCard() -> some View {
        self
            .background(Color.bhSurface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bhBorder, lineWidth: 1))
    }

    /// Applies the standard section title typography.
    func bhSectionTitle() -> some View {
        self
            .font(.bhSectionTitle)
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundColor(.bhMuted)
    }
}

// MARK: - Color Scheme Preference

/// User-controllable color scheme override. Persists in `UserDefaults`
/// and is applied via the `.bhColorScheme()` modifier on every view that
/// needs to enforce a scheme (root + each sheet).
enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Resolves to the SwiftUI scheme to apply (`nil` = follow system).
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

private struct BHColorSchemeModifier: ViewModifier {
    @AppStorage("colorSchemePref") private var pref: String = ColorSchemePreference.dark.rawValue
    func body(content: Content) -> some View {
        let resolved = ColorSchemePreference(rawValue: pref) ?? .dark
        return content.preferredColorScheme(resolved.scheme)
    }
}

extension View {
    /// Applies the user-selected color scheme preference. Must be set on
    /// the root view AND every sheet (sheets create new presentation
    /// contexts that don't inherit `preferredColorScheme`).
    func bhColorScheme() -> some View {
        modifier(BHColorSchemeModifier())
    }
}

// MARK: - Currency Manager

/// Manages the app-wide currency formatter. The currency code is set from
/// `AppSettings.currencyCode` on launch; changes rebuild the formatter so
/// all `.asCurrency` calls pick up the new symbol and decimal rules.
enum CurrencyManager {
    private static var _code: String = {
        let saved = UserDefaults.standard.string(forKey: "currencyCode") ?? ""
        if !saved.isEmpty { return saved }
        return Locale.current.currency?.identifier ?? "USD"
    }()
    private static var _formatter: NumberFormatter = makeFormatter(_code)

    static var currencyCode: String {
        get { _code }
        set {
            let resolved = newValue.isEmpty ? (Locale.current.currency?.identifier ?? "USD") : newValue
            guard resolved != _code else { return }
            _code = resolved
            _formatter = makeFormatter(resolved)
            UserDefaults.standard.set(newValue, forKey: "currencyCode")
        }
    }

    static var formatter: NumberFormatter { _formatter }

    static var symbol: String { _formatter.currencySymbol ?? _code }

    /// The resolved code (never empty — returns the auto-detected code when
    /// the user hasn't chosen one).
    static var resolvedCode: String { _code }

    private static func makeFormatter(_ code: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        f.locale = Locale.current
        return f
    }
}

// MARK: - Double + Currency Formatting

extension Double {
    /// Formats this value as a localized currency string using the app-wide
    /// `CurrencyManager.formatter`.
    var asCurrency: String {
        CurrencyManager.formatter.string(from: NSNumber(value: self)) ?? String(format: "%.2f", self)
    }
}
