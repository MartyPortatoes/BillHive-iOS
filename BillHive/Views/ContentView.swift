import SwiftUI

// MARK: - Content View

/// Root tab bar view containing all five main sections of the app.
///
/// Handles global concerns: error banner display, toast overlay,
/// dark color scheme enforcement, and scene-phase driven data refresh.
struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel
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
        }
        .animation(.easeInOut(duration: 0.25), value: vm.toastMessage)
        .animation(.easeInOut(duration: 0.25), value: vm.error)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            if phase == .active && !vm.isLocal {
                Task { await vm.refresh() }
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
                .fill(Color(hex: "#F5A800") ?? .orange)
                .frame(width: 8, height: 8)
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color(hex: "#e4e5e8") ?? .white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#1c1e22") ?? Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "#34373d") ?? Color(.separator), lineWidth: 1)
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
                        .font(.bhBodySecondary)
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

/// App-wide color palette — dark theme inspired by the BillHive web app.
///
/// Each color maps to the web app's CSS custom properties for visual consistency.
extension Color {
    static let bhBackground = Color(hex: "#0c0d0f") ?? Color(.systemBackground)
    static let bhSurface = Color(hex: "#141518") ?? Color(.secondarySystemBackground)
    static let bhSurface2 = Color(hex: "#1c1e22") ?? Color(.tertiarySystemBackground)
    static let bhSurface3 = Color(hex: "#242629") ?? Color(.systemGray5)
    static let bhBorder = Color(hex: "#2a2c31") ?? Color(.separator)
    static let bhBorder2 = Color(hex: "#34373d") ?? Color(.separator)
    static let bhText = Color(hex: "#e4e5e8") ?? .primary
    static let bhMuted = Color(hex: "#767880") ?? .secondary
    static let bhMuted2 = Color(hex: "#4a4c52") ?? Color(.systemGray3)
    static let bhAmber = Color(hex: "#F5A800") ?? .orange
    static let bhBlue = Color(hex: "#5bc4f5") ?? .blue
    static let bhRed = Color(hex: "#ef5350") ?? .red
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
    /// Primary body text — card titles, bill/person names.
    static let bhBody = Font.subheadline.weight(.semibold).monospaced()
    /// Secondary body text — row content, inputs.
    static let bhBodySecondary = Font.footnote.monospaced()
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
