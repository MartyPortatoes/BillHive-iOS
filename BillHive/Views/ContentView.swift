import SwiftUI
import UIKit

// MARK: - Content View

/// Root tab bar view containing all five main sections of the app.
///
/// Handles global concerns: error banner display, toast overlay,
/// dark color scheme enforcement, and scene-phase driven data refresh.
struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @StateObject private var lock = AppLockManager.shared
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Error banner — shown when load() fails
                if let err = vm.error {
                    ErrorBannerView(message: err) {
                        vm.error = nil
                        Task { await vm.load() }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                TabView(selection: $selectedTab) {
                    BillsView()
                        .tabItem {
                            Label("Bills", systemImage: "list.clipboard")
                        }
                        .tag(0)

                    SummaryView()
                        .tabItem {
                            Label("Summary", systemImage: "dollarsign.circle")
                        }
                        .tag(1)

                    SendReceiveView()
                        .tabItem {
                            Label("Pay & Collect", systemImage: "arrow.up.arrow.down.circle")
                        }
                        .tag(2)

                    TrendsView()
                        .tabItem {
                            Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        .tag(3)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag(4)
                }
                .tint(Color(hex: "#F5A800"))
            }

            // Toast overlay — positioned above the tab bar
            if let msg = vm.toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(999)
                    .padding(.bottom, 90)
            }

            // Privacy overlay — covers the app while scenePhase is .inactive
            // (the moment iOS captures the App Switcher snapshot) or .background.
            // Without this, the snapshot would expose financial amounts, names,
            // server hostnames, and (for SelfHive) email addresses to anyone
            // who scrolls through the App Switcher on an unlocked device.
            if scenePhase != .active {
                PrivacyOverlayView()
                    .transition(.opacity)
                    .zIndex(1000)
            }

            // App Lock — full-screen biometric/passcode gate when enabled.
            // Sits above the privacy overlay so that as the app returns to
            // foreground after a timeout, the lock screen is what's revealed.
            if lock.isLocked {
                AppLockView(lock: lock)
                    .transition(.opacity)
                    .zIndex(1001)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.toastMessage)
        .animation(.easeInOut(duration: 0.25), value: vm.error)
        .animation(.easeInOut(duration: 0.15), value: scenePhase)
        .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
        .bhColorScheme()
        .onChange(of: scenePhase) { phase in
            lock.handleScenePhase(phase)
            // Don't refresh from server while we're behind the lock — would
            // pull data into a view the user isn't authenticated for yet.
            if phase == .active && !vm.isLocal && !lock.isLocked {
                Task { await vm.refresh() }
            }
        }
    }
}

// MARK: - Privacy Overlay

/// Solid background + logo shown over the entire app whenever the scene is
/// not `.active`. Prevents the iOS App Switcher snapshot from capturing
/// sensitive financial data, email addresses, or server URLs.
struct PrivacyOverlayView: View {
    var body: some View {
        ZStack {
            Color.bhBackground
                .ignoresSafeArea()
            VStack(spacing: 14) {
                TriHexLogoMark(size: 56)
                Text("BillHive")
                    .font(.title2.weight(.heavy))
                    .foregroundColor(.bhText)
            }
        }
    }
}

// MARK: - Error Banner

/// A top-aligned banner that displays an error message with a retry button.
struct ErrorBannerView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.bhAmber)
                .font(.subheadline)
            Text(message)
                .font(.bhCaption)
                .foregroundColor(.bhText)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: onRetry)
                .font(.bhCaption.weight(.semibold))
                .foregroundColor(.bhAmber)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bhSurface)
        .overlay(Rectangle().fill(Color.bhBorder).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Toast

/// A floating toast notification shown at the bottom of the screen.
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.bhAmber)
                .frame(width: 8, height: 8)
            Text(message)
                .font(.bhCaption)
                .foregroundColor(.bhText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bhSurface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.bhBorder2, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

// MARK: - Empty State

/// A reusable empty-state placeholder with an icon, title, subtitle, and optional CTA.
///
/// Use in any view that may render with no data — gives the user a clear next
/// action rather than a blank scroll view.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.bhAmber.opacity(0.1))
                    .frame(width: 88, height: 88)
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundColor(.bhAmber)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.bhBody)
                    .foregroundColor(.bhText)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "plus")
                }
                .buttonStyle(BHPrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }
}

// MARK: - Design Tokens

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

// MARK: - Semantic Font Tokens
//
// All fonts scale with Dynamic Type. The `.monospacedDigit()` modifier
// keeps decimal alignment without forcing a full monospaced design on
// non-numeric text. Use `.monospaced()` only where glyph-grid alignment
// matters (section labels, code-like text).
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

// MARK: - Money Formatting

/// Shared `NumberFormatter` for currency display, avoiding repeated allocation.
///
/// Configured for USD with exactly 2 decimal places. Thread-safe because
/// `NumberFormatter` is a class and this instance is only read after initial setup.
private let currencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencySymbol = "$"
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

extension Double {
    /// Formats the value as a US dollar amount (e.g. "$1,234.56").
    var asCurrency: String {
        currencyFormatter.string(from: NSNumber(value: self)) ?? "$\(String(format: "%.2f", self))"
    }
}
