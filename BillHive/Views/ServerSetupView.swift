import SwiftUI

// MARK: - Server Setup View

/// Initial onboarding screen for the SelfHive (remote server) target.
///
/// Presents a connection form where the user enters their self-hosted
/// server URL, tests the connection via `/api/health`, and connects.
/// Once connected, the URL is persisted in `@AppStorage` and the app
/// transitions to `ContentView`.
struct ServerSetupView: View {
    @EnvironmentObject var vm: AppViewModel
    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("backupServerURL") private var backupServerURL: String = ""

    // Primary
    @State private var inputURL = ""
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var testSuccess = false

    // Backup (optional)
    @State private var showBackupField = false
    @State private var backupInputURL = ""
    @State private var isTestingBackup = false
    @State private var backupTestResult: String? = nil
    @State private var backupTestSuccess = false

    var body: some View {
        ZStack {
            HexBGView().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Logo
                    VStack(spacing: 12) {
                        TriHexLogoMark(size: 72)
                        Text("SelfHive")
                            .font(.largeTitle.weight(.black))
                            .foregroundColor(.bhText)
                        Text("self-hosted bill manager")
                            .font(.bhCaption)
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundColor(.bhMuted)
                    }
                    .padding(.top, 40)

                    // Setup card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Connect to your SelfHive server")
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundColor(.bhText)

                        Text("Enter the URL of your self-hosted SelfHive instance.")
                            .font(.bhBodySecondary)
                            .foregroundColor(.bhMuted)

                        // Primary URL field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server URL")
                                .bhSectionTitle()

                            TextField("http://192.168.1.100:8080", text: $inputURL)
                                .textFieldStyle(.plain)
                                .font(.bhBodySecondary)
                                .foregroundColor(.bhText)
                                .padding(10)
                                .background(Color.bhSurface2)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                        }

                        if let result = testResult {
                            HStack(spacing: 6) {
                                Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(testSuccess ? .bhAmber : .bhRed)
                                Text(result)
                                    .font(.bhCaption)
                                    .foregroundColor(testSuccess ? .bhAmber : .bhRed)
                            }
                        }

                        // Backup URL section (collapsible)
                        if showBackupField {
                            backupURLSection
                        } else {
                            Button {
                                withAnimation { showBackupField = true }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                        .font(.bhBodySecondary)
                                    Text("Add backup server (optional)")
                                        .font(.bhBodySecondary)
                                }
                                .foregroundColor(.bhAmber)
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                Task { await testPrimary() }
                            } label: {
                                HStack {
                                    if isTesting {
                                        ProgressView().tint(.bhText).scaleEffect(0.7)
                                    }
                                    Text(isTesting ? "Testing..." : "Test Connection")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BHSecondaryButtonStyle())
                            .disabled(inputURL.isEmpty || isTesting)

                            Button {
                                saveAndConnect()
                            } label: {
                                Text("Connect")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BHPrimaryButtonStyle())
                            .disabled(inputURL.isEmpty || !testSuccess)
                        }
                    }
                    .padding(20)
                    .bhCard()
                    .padding(.horizontal, 24)

                    if showBackupField {
                        Text("The app will automatically fall back to the backup if the primary server is unreachable.")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Text("Self-hosted · Your data stays on your server")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted2)
                        .padding(.bottom, 24)
                }
            }
        }
        .bhColorScheme()
    }

    // MARK: - Backup URL Section

    @ViewBuilder
    private var backupURLSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Backup Server URL")
                    .bhSectionTitle()
                Spacer()
                Button {
                    withAnimation {
                        showBackupField = false
                        backupInputURL = ""
                        backupTestResult = nil
                        backupTestSuccess = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.bhMuted)
                }
            }

            TextField("http://100.x.y.z:8080", text: $backupInputURL)
                .textFieldStyle(.plain)
                .font(.bhBodySecondary)
                .foregroundColor(.bhText)
                .padding(10)
                .background(Color.bhSurface2)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)

            if let result = backupTestResult {
                HStack(spacing: 6) {
                    Image(systemName: backupTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(backupTestSuccess ? .bhAmber : .bhRed)
                    Text(result)
                        .font(.bhCaption)
                        .foregroundColor(backupTestSuccess ? .bhAmber : .bhRed)
                }
            }

            Button {
                Task { await testBackup() }
            } label: {
                HStack {
                    if isTestingBackup {
                        ProgressView().tint(.bhText).scaleEffect(0.7)
                    }
                    Text(isTestingBackup ? "Testing..." : "Test Backup")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BHSecondaryButtonStyle())
            .disabled(backupInputURL.isEmpty || isTestingBackup)
        }
    }

    // MARK: - Actions

    private func testPrimary() async {
        isTesting = true
        testResult = nil
        let result = await APIClient.testConnection(rawURL: inputURL)
        testSuccess = result.success
        testResult = result.message
        isTesting = false
    }

    private func testBackup() async {
        isTestingBackup = true
        backupTestResult = nil
        let result = await APIClient.testConnection(rawURL: backupInputURL)
        backupTestSuccess = result.success
        backupTestResult = result.message
        isTestingBackup = false
    }

    private func saveAndConnect() {
        serverURL = inputURL
        APIClient.shared.serverURL = inputURL
        // Save backup only if it tested successfully (or skip silently if blank)
        if showBackupField && backupTestSuccess && !backupInputURL.isEmpty {
            backupServerURL = backupInputURL
            APIClient.shared.backupServerURL = backupInputURL
        }
    }
}

// MARK: - Tri-Hex Logo Mark

/// Three-hexagon logo matching the BillHive website SVG (viewBox 100×100).
///
/// Draws three filled hexagons in an asymmetric cluster: one on the left,
/// one top-right, and one bottom-right, all in the brand amber color.
struct TriHexLogoMark: View {
    let size: CGFloat

    // SVG points scaled from 100×100 viewBox to `size`
    private func hex(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        let scaled = pts.map { CGPoint(x: $0.0 / 100 * size, y: $0.1 / 100 * size) }
        path.move(to: scaled[0])
        scaled.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    var body: some View {
        ZStack {
            // Left hex
            hex([(48.6,50),(41.2,62.8),(26.4,62.8),(19,50),(26.4,37.2),(41.2,37.2)])
                .fill(Color.bhAmber)
            // Top-right hex
            hex([(72.9,36),(65.5,48.8),(50.7,48.8),(43.3,36),(50.7,23.2),(65.5,23.2)])
                .fill(Color.bhAmber)
            // Bottom-right hex
            hex([(72.9,64),(65.5,76.8),(50.7,76.8),(43.3,64),(50.7,51.2),(65.5,51.2)])
                .fill(Color.bhAmber)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Hex Logo Mark

/// A single hexagon with a stylized "bill" icon inside — three horizontal
/// bars of decreasing width, resembling a receipt or invoice.
struct HexLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            HexShape()
                .fill(Color.bhAmber)
                .frame(width: size, height: size * CGFloat(3).squareRoot() / 2)
            // Bill icon
            VStack(spacing: size * 0.06) {
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.45, height: size * 0.09)
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.6, height: size * 0.09)
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.35, height: size * 0.09)
            }
        }
    }
}

// MARK: - Hex Shape

/// A flat-top regular hexagon shape that fills the given rect.
struct HexShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let points: [CGPoint] = [
            CGPoint(x: w * 0.25, y: 0),
            CGPoint(x: w * 0.75, y: 0),
            CGPoint(x: w, y: h * 0.5),
            CGPoint(x: w * 0.75, y: h),
            CGPoint(x: w * 0.25, y: h),
            CGPoint(x: 0, y: h * 0.5)
        ]
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Button Styles

/// Solid amber background with dark text. Used for primary call-to-action buttons.
struct BHPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bhBodySecondary.weight(.semibold))
            .foregroundColor(Color(hex: "#0c0d0f"))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(isEnabled ? Color.bhAmber : Color.bhAmber.opacity(0.4))
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Surface-colored background with a border outline. Used for secondary actions.
struct BHSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bhBodySecondary.weight(.medium))
            .foregroundColor(.bhText)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.bhSurface2)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Surface background with a red border and red text. Used for destructive actions.
struct BHDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bhBodySecondary.weight(.medium))
            .foregroundColor(.bhRed)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.bhSurface2)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhRed, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
