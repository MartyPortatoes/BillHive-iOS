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

    // API key (optional, for self-hosted servers that require device keys)
    @State private var showApiKeyField = false
    @State private var inputApiKey = ""

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

                        // API key section (collapsible, auto-expanded when the
                        // server reports it requires device keys).
                        if showApiKeyField {
                            apiKeySection
                        } else {
                            Button {
                                withAnimation { showApiKeyField = true }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "key.fill")
                                        .font(.bhBodySecondary)
                                    Text("Add API key (optional)")
                                        .font(.bhBodySecondary)
                                }
                                .foregroundColor(.bhAmber)
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                Task { await testPrimary() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isTesting {
                                        ProgressView().tint(.bhText).scaleEffect(0.7)
                                    }
                                    Text(isTesting ? "Testing..." : "Test Connection")
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
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

    // MARK: - API Key Section

    @ViewBuilder
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("API Key")
                    .bhSectionTitle()
                Spacer()
                Button {
                    withAnimation {
                        showApiKeyField = false
                        inputApiKey = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.bhMuted)
                }
            }

            SecureField("bh_live_…", text: $inputApiKey)
                .textFieldStyle(.plain)
                .font(.bhBodySecondary)
                .foregroundColor(.bhText)
                .padding(10)
                .background(Color.bhSurface2)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Text("If your server requires API keys (Settings → Connected Devices in BillHive web), paste yours here. Otherwise leave blank.")
                .font(.bhCaption)
                .foregroundColor(.bhMuted)
                .lineLimit(nil)
        }
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
        let result = await APIClient.testConnection(rawURL: inputURL, apiKey: inputApiKey)
        testSuccess = result.success
        testResult = result.message
        // Auto-reveal the API key field when the server reports it requires
        // keys but we didn't (or don't have a working) one.
        if result.requiresKey && inputApiKey.isEmpty {
            withAnimation { showApiKeyField = true }
        }
        isTesting = false
    }

    private func testBackup() async {
        isTestingBackup = true
        backupTestResult = nil
        let result = await APIClient.testConnection(rawURL: backupInputURL, apiKey: inputApiKey)
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
        // Persist the API key (or clear if empty) — KeychainHelper handles
        // the deletion case automatically when given an empty string.
        if showApiKeyField {
            APIClient.shared.apiKey = inputApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// Logo shapes (TriHexLogoMark, HexLogoMark, HexShape) and button styles
// (BHPrimaryButtonStyle, BHSecondaryButtonStyle, BHDangerButtonStyle) are
// defined in Utilities/BrandComponents.swift.
