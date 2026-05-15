import SwiftUI
import UIKit

// MARK: - Design Tokens (Colors)
//
// Warm-earthy redesign of the BillHive palette.
//
// LIGHT  — cream paper surfaces, espresso text, muted honey brand,
//          plus an expanded set of earthy semantic accents.
// DARK   — rich cocoa surfaces (not near-black), warm cream text, and the
//          brand pivots from honey to LIGHT SKY BLUE. The token names
//          keep their `bh*` light-mode aliases (`bhAmber`, `bhHoneyDeep`,
//          `bhHoneySoft`) so consuming views don't have to branch — the
//          same symbol resolves honey in light mode, sky in dark mode.
//
// All hex values are pulled directly from `colors_and_type.css` shipped
// alongside this file.
extension Color {
    // ── Surfaces ─────────────────────────────────────────────────────────
    // LIGHT: cream paper.  DARK: rich cocoa (not near-black).
    static let bhBackground = Color.bhDynamic(light: "#f4ecda", dark: "#221810")
    static let bhSurface    = Color.bhDynamic(light: "#fbf5e8", dark: "#332618")
    static let bhSurface2   = Color.bhDynamic(light: "#ede1c6", dark: "#332618")
    static let bhSurface3   = Color.bhDynamic(light: "#e0d2b1", dark: "#332618")
    static let bhBorder     = Color.bhDynamic(light: "#d8c8a4", dark: "#7a6442")
    static let bhBorder2    = Color.bhDynamic(light: "#b8a578", dark: "#8a7450")

    // ── Text ─────────────────────────────────────────────────────────────
    static let bhText       = Color.bhDynamic(light: "#2b1d11", dark: "#f0e6d0")
    static let bhText2      = Color.bhDynamic(light: "#4a3826", dark: "#d4c5a0")
    static let bhMuted      = Color.bhDynamic(light: "#7a6a52", dark: "#a08e6e")
    static let bhMuted2     = Color.bhDynamic(light: "#a08e72", dark: "#786750")

    // ── Brand — honey in light, sky blue in dark ─────────────────────────
    // Symbol names kept (bhAmber / bhHoneyDeep / bhHoneySoft) so existing
    // call sites don't have to branch — the same token resolves to honey
    // when the system is light, sky when dark.
    static let bhAmber      = Color.bhDynamic(light: "#d8923e", dark: "#7eb8d6")
    static let bhHoneyDeep  = Color.bhDynamic(light: "#b8721e", dark: "#5497b8")
    static let bhHoneySoft  = Color.bhDynamic(light: "#f0c073", dark: "#b4d5e6")

    // ── Semantic status (existing names kept, hex updated) ───────────────
    static let bhBlue       = Color.bhDynamic(light: "#6fa5c4", dark: "#8fc4dd")
    static let bhRed        = Color.bhDynamic(light: "#a04a2e", dark: "#c46a4a")
    static let bhGreen      = Color.bhDynamic(light: "#5b6f3f", dark: "#8aa468")

    // ── New earthy semantic accents ──────────────────────────────────────
    static let bhClay       = Color.bhDynamic(light: "#b8654a", dark: "#d18570")
    static let bhOlive      = Color.bhDynamic(light: "#7e8556", dark: "#a3ad78")
    static let bhPlum       = Color.bhDynamic(light: "#8b5a6f", dark: "#b58496")

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

// MARK: - Bill Category Fills
//
// Fills used behind bill emoji glyphs. These are NEW — the previous palette
// re-used `bhAmber` and a couple of system colors. The redesign gives each
// utility category its own warm hue so the bill grid reads as a varied
// landscape, not a wall of amber.
enum BHBillFill {
    static let electric  = Color(hex: "#c87a2e") ?? .orange   // burnt orange
    static let gas       = Color(hex: "#c4933a") ?? .yellow   // gold
    static let water     = Color(hex: "#6fa5c4") ?? .blue     // sky
    static let internet  = Color(hex: "#8b6f9b") ?? .purple   // dusty plum
    static let mortgage  = Color(hex: "#7e8556") ?? .green    // olive
    static let mobile    = Color(hex: "#5b8a8a") ?? .teal     // teal slate
    static let trash     = Color(hex: "#846f56") ?? .brown    // taupe
    static let other     = Color(hex: "#a89880") ?? .gray     // sand
}

// MARK: - Design Tokens (Fonts)
//
// UNCHANGED in this redesign. The iOS app renders via SwiftUI's Font.title3 /
// .subheadline / etc., which resolve to SF Pro on-device. The HTML mocks ship
// with a `-apple-system, "SF Pro Display"…` stack so they match. Earlier
// preview screenshots that showed a Vollkorn serif were a redesign-time
// substitution and have been reverted.
extension Font {
    /// Large view header title (e.g. "Bills", "Summary").
    static let bhViewTitle = Font.title3.weight(.bold)
    /// Subtitle under view headers — short description line.
    static let bhSubtitle = Font.footnote
    /// Uppercase section title inside cards.
    static let bhSectionTitle = Font.caption2.weight(.medium).monospacedDigit()
    /// Primary body text — used for tabular content. Digits align, letters stay proportional.
    static let bhBody = Font.subheadline.weight(.semibold).monospacedDigit()
    /// Secondary body text — row content, inputs. Digits align, letters stay proportional.
    static let bhBodySecondary = Font.footnote.monospacedDigit()
    /// Proportional name text — bill names, person names, prose labels.
    /// Use this instead of `bhBody` whenever the text is a proper noun or sentence.
    static let bhBodyName = Font.subheadline.weight(.semibold)
    /// Proportional secondary name text — sub-labels, hint copy under titles.
    static let bhBodyNameSecondary = Font.footnote
    /// Small caption / hint text.
    static let bhCaption = Font.caption2.monospacedDigit()
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

    // ── Warm shadow stack (NEW — optional polish) ────────────────────────
    // Umber-tinted shadows that match the cream surfaces. Drop in wherever a
    // pure-black SwiftUI `.shadow(...)` is currently used.
    func bhShadow1() -> some View { shadow(color: bhShadowUmber.opacity(0.06), radius: 2,  y: 1)  }
    func bhShadow2() -> some View { shadow(color: bhShadowUmber.opacity(0.08), radius: 12, y: 4)  }
    func bhShadow3() -> some View { shadow(color: bhShadowUmber.opacity(0.12), radius: 32, y: 12) }
    /// Honey glow — for hero CTAs and highlighted hex tiles.
    func bhHoneyGlow() -> some View { shadow(color: Color.bhAmber.opacity(0.28), radius: 28, y: 8) }
}

private let bhShadowUmber = Color(red: 0.29, green: 0.22, blue: 0.15)

// MARK: - Color Scheme Preference

/// User-controllable color scheme override. Persists in `UserDefaults`
/// and is applied via the `.bhColorScheme()` modifier on every view that
/// needs to enforce a scheme (root + each sheet).
enum ColorSchemePreference: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }

    /// Resolves to the SwiftUI scheme to apply.
    var scheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark:  return .dark
        }
    }
}

private struct BHColorSchemeModifier: ViewModifier {
    @AppStorage("colorSchemePref") private var pref: String = ""
    func body(content: Content) -> some View {
        // Unknown/empty pref (first launch, or old "system" value) → follow system.
        let resolved = ColorSchemePreference(rawValue: pref)
        return content.preferredColorScheme(resolved?.scheme)
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
