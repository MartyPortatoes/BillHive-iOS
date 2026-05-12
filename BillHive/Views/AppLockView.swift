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

    /// Prompts the user to authenticate with biometrics (Face ID / Touch ID).
    ///
    /// Primary path uses `.deviceOwnerAuthenticationWithBiometrics` so that
    /// the system passcode is NOT offered as a fallback — the whole point of
    /// the feature is that only the enrolled face/finger can unlock.
    ///
    /// If biometrics become temporarily unavailable (locked out after too many
    /// failures, or disabled in Settings after enrollment), we fall back to
    /// `.deviceOwnerAuthentication` (passcode) to prevent soft-locking the
    /// user out of the app entirely.
    @discardableResult
    func unlock() async -> Bool {
        let context = LAContext()
        // Hide the "Enter Password" fallback button on the biometric prompt.
        context.localizedFallbackTitle = ""

        var probeError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &probeError) {
            // Happy path: biometrics available — require them, no passcode.
            do {
                let ok = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Unlock BillHive"
                )
                if ok { isLocked = false }
                return ok
            } catch {
                return false
            }
        } else {
            // Biometrics unavailable (locked out, unenrolled after setup, etc.).
            // Fall back to passcode to prevent permanent soft-lock.
            let fallback = LAContext()
            var fallbackError: NSError?
            guard fallback.canEvaluatePolicy(.deviceOwnerAuthentication, error: &fallbackError) else {
                // No auth mechanism at all — let the user in.
                isLocked = false
                return true
            }
            do {
                let ok = try await fallback.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Biometrics unavailable — enter passcode to unlock BillHive"
                )
                if ok { isLocked = false }
                return ok
            } catch {
                return false
            }
        }
    }

    /// Called when the user flips the toggle ON in Settings. Requires actual
    /// biometric authentication — if the device has no biometrics enrolled
    /// the feature cannot be enabled.
    @discardableResult
    func tryEnable() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""

        var probeError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &probeError) else {
            // No biometrics available — cannot enable the feature.
            return false
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
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

// MARK: - Biometry Helpers

extension AppLockManager {
    /// The biometry type available on this device.
    nonisolated static var currentBiometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    /// Human-readable name for the device's biometry type.
    nonisolated static var biometryDisplayName: String {
        switch currentBiometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Device Passcode"
        }
    }

    /// SF Symbol name for the device's biometry type.
    nonisolated static var biometrySymbolName: String {
        switch currentBiometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default: return "lock.fill"
        }
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
                        Image(systemName: AppLockManager.biometrySymbolName)
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

