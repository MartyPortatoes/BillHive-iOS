import SwiftUI
import LocalAuthentication

// MARK: - App Lock Manager

/// Optional Face ID / Touch ID / passcode gate for the entire app.
///
/// Off by default. When the user enables it in Settings → Privacy & Security,
/// the app locks on cold start and on returning from background after the
/// configured timeout. Brief `.inactive` transitions (notification banners,
/// Control Center swipes, App Switcher peeks) do NOT cause a re-lock — only
/// a full `.background` followed by `.active` does.
///
/// Threat model: stops a casual snoop or thief from reading bills, names,
/// amounts, and email addresses on an unlocked-but-unattended phone. Does
/// NOT protect against forensic extraction on a jailbroken device — for
/// that, see the file-protection upgrade in MASVS-L2.
@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    /// Whether the lock feature is enabled. Persisted in UserDefaults so it
    /// survives launches; deliberately NOT iCloud-synced — each device decides
    /// on its own (a stolen iPad shouldn't auto-lock just because the iPhone
    /// happens to have the feature on).
    @AppStorage("appLockEnabled") var isEnabled: Bool = false {
        didSet { objectWillChange.send() }
    }

    /// How long the app may stay backgrounded before re-locking (seconds).
    /// 0 = immediate. Defaults to 5 minutes.
    @AppStorage("appLockTimeoutSeconds") var timeoutSeconds: Int = 300 {
        didSet { objectWillChange.send() }
    }

    /// Whether the app is currently locked. Drives the lock-screen overlay
    /// in ContentView. On cold start this mirrors `isEnabled`.
    @Published var isLocked: Bool

    /// Wall-clock time of the most recent transition into `.background`.
    /// Cleared once we re-evaluate on return to `.active`.
    private var backgroundedAt: Date?

    private init() {
        // Lock on cold start if the feature was enabled before terminating.
        let enabled = UserDefaults.standard.bool(forKey: "appLockEnabled")
        self.isLocked = enabled
    }

    // MARK: - Scene phase

    /// Called from ContentView's scenePhase observer. Records timestamps on
    /// background and re-evaluates the lock on return to active.
    func handleScenePhase(_ phase: ScenePhase) {
        guard isEnabled else { return }
        switch phase {
        case .background:
            // Only stamp on full background — `.inactive` is too aggressive.
            backgroundedAt = Date()
        case .active:
            if let ts = backgroundedAt {
                let elapsed = Int(Date().timeIntervalSince(ts))
                if elapsed >= timeoutSeconds {
                    isLocked = true
                }
                backgroundedAt = nil
            }
        default:
            break
        }
    }

    // MARK: - Authentication

    /// Prompts the user to authenticate. Falls back from biometrics to the
    /// device passcode automatically. Returns whether the unlock succeeded.
    ///
    /// If the device has no passcode set at all (so we can't gate anything),
    /// we set `isLocked = false` so the user isn't soft-bricked at the lock
    /// screen — better to let them in than trap them.
    @discardableResult
    func unlock() async -> Bool {
        let context = LAContext()
        var probeError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probeError) else {
            // No passcode set, biometrics unavailable, etc.
            isLocked = false
            return true
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock BillHive"
            )
            if ok { isLocked = false }
            return ok
        } catch {
            return false
        }
    }

    /// Called when the user flips the toggle ON in Settings. Verifies they
    /// can actually authenticate BEFORE we persist `isEnabled = true`, so
    /// they can never lock themselves out.
    @discardableResult
    func tryEnable() async -> Bool {
        let context = LAContext()
        var probeError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probeError) else {
            return false
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Enable BillHive App Lock"
            )
            if ok { isEnabled = true }
            return ok
        } catch {
            return false
        }
    }

    /// User flips the toggle OFF. No auth required to disable — the user is
    /// already in the app, having presumably authenticated to get here.
    func disable() {
        isEnabled = false
        isLocked = false
        backgroundedAt = nil
    }
}

// MARK: - Biometry helpers

private func currentBiometryType() -> LABiometryType {
    let ctx = LAContext()
    _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    return ctx.biometryType
}

private func biometryDisplayName() -> String {
    switch currentBiometryType() {
    case .faceID: return "Face ID"
    case .touchID: return "Touch ID"
    case .opticID: return "Optic ID"
    default: return "Device Passcode"
    }
}

private func biometrySymbolName() -> String {
    switch currentBiometryType() {
    case .faceID: return "faceid"
    case .touchID: return "touchid"
    case .opticID: return "opticid"
    default: return "lock.fill"
    }
}

// MARK: - Lock Screen

/// Full-screen overlay shown while the app is locked. Auto-prompts for
/// authentication on appear; if the user cancels, they can tap "Unlock"
/// to retry.
struct AppLockView: View {
    @ObservedObject var lock: AppLockManager
    @State private var lastAttemptFailed = false

    var body: some View {
        ZStack {
            Color.bhBackground.ignoresSafeArea()
            VStack(spacing: 24) {
                TriHexLogoMark(size: 72)
                Text("BillHive")
                    .font(.title.weight(.heavy))
                    .foregroundColor(.bhText)
                    .padding(.bottom, 8)

                Button {
                    Task { await tryUnlock() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: biometrySymbolName())
                        Text("Unlock")
                    }
                    .frame(maxWidth: 220)
                }
                .buttonStyle(BHPrimaryButtonStyle())

                if lastAttemptFailed {
                    Text("Authentication failed. Tap Unlock to try again.")
                        .font(.bhCaption)
                        .foregroundColor(.bhRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
        .task {
            // Auto-prompt on appear (cold start or re-lock after timeout).
            await tryUnlock()
        }
    }

    private func tryUnlock() async {
        let ok = await lock.unlock()
        lastAttemptFailed = !ok
    }
}

// MARK: - Privacy & Security Settings Sheet

/// Settings sheet for the App Lock feature, opened from Settings → Privacy & Security.
struct PrivacySecuritySheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var lock = AppLockManager.shared
    @State private var enableError: String?
    @State private var isAuthenticating = false

    var body: some View {
        NavigationStack {
            ZStack {
                HexBGView().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        SettingsSection(title: "App Lock") {
                            Toggle(isOn: Binding(
                                get: { lock.isEnabled },
                                set: { newValue in handleToggle(newValue) }
                            )) {
                                HStack(spacing: 8) {
                                    Image(systemName: biometrySymbolName())
                                        .foregroundColor(.bhAmber)
                                    Text("Require \(biometryDisplayName())")
                                        .foregroundColor(.bhText)
                                }
                            }
                            .tint(.bhAmber)
                            .disabled(isAuthenticating)

                            if lock.isEnabled {
                                Divider().background(Color.bhBorder)
                                HStack {
                                    Text("Auto-lock after")
                                        .font(.bhBodySecondary)
                                        .foregroundColor(.bhMuted)
                                    Spacer()
                                    Picker("", selection: Binding(
                                        get: { lock.timeoutSeconds },
                                        set: { lock.timeoutSeconds = $0 }
                                    )) {
                                        Text("Immediately").tag(0)
                                        Text("1 minute").tag(60)
                                        Text("5 minutes").tag(300)
                                        Text("15 minutes").tag(900)
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.bhAmber)
                                }
                            }

                            if let err = enableError {
                                Text(err)
                                    .font(.bhCaption)
                                    .foregroundColor(.bhRed)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 16)

                        Text("When enabled, BillHive requires \(biometryDisplayName()) to open the app on cold start and after returning from the background.")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.top, 4)

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Privacy & Security")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.bhAmber)
                }
            }
        }
        .bhColorScheme()
    }

    private func handleToggle(_ newValue: Bool) {
        enableError = nil
        if newValue {
            isAuthenticating = true
            Task {
                let ok = await lock.tryEnable()
                if !ok {
                    enableError = "Couldn't authenticate. Make sure \(biometryDisplayName()) is enabled in iOS Settings, and that you have a device passcode set."
                }
                isAuthenticating = false
            }
        } else {
            lock.disable()
        }
    }
}
