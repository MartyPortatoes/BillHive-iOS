import SwiftUI

// MARK: - Content View

/// Root tab bar view containing all five main sections of the app.
///
/// Handles global concerns: error banner display, toast overlay,
/// dark color scheme enforcement, and scene-phase driven data refresh.
struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @StateObject private var lock = AppLockManager.shared
    @State private var selectedTab = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasCompletedOnboarding)
        .bhColorScheme()
    }

    /// Main app shell shown after onboarding is complete.
    private var mainContent: some View {
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
                .tint(.bhAmber)
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
        .onChange(of: scenePhase) { phase in
            lock.handleScenePhase(phase)
            // Don't refresh from server while we're behind the lock — would
            // pull data into a view the user isn't authenticated for yet.
            if phase == .active && !vm.isLocal && !lock.isLocked {
                Task { await vm.refresh() }
            }
            // Flush any in-flight debounced save before the OS may suspend
            // the app — otherwise the user's last edit can be lost.
            if phase == .inactive || phase == .background {
                Task { await vm.flushPendingSave() }
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
                #if BILLHIVE_LOCAL
                Text("BillHive")
                    .font(.title2.weight(.heavy))
                    .foregroundColor(.bhText)
                #else
                Text("SelfHive")
                    .font(.title2.weight(.heavy))
                    .foregroundColor(.bhText)
                #endif
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

// Design tokens (Color.bh*, Font.bh*, CurrencyManager, etc.) are defined in
// Utilities/Theme.swift. Button styles and logo shapes live in
// Utilities/BrandComponents.swift.
