import SwiftUI

// MARK: - Settings View

/// Top-level settings screen — a compact list of category rows. Each row
/// opens a full-screen sheet for that category (Household, Server, etc.),
/// matching the same pattern used by the bill editor.
///
/// Reduces the cognitive load of a single long-scrolling settings page by
/// grouping related controls and presenting them on demand.
struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("backupServerURL") private var backupServerURL: String = ""
    @AppStorage("colorSchemePref") private var colorSchemePref: String = ColorSchemePreference.dark.rawValue

    // Category sheets
    @State private var showCurrency = false
    @State private var showHousehold = false
    @State private var showEmailRelay = false
    @State private var showServerEdit = false
    @State private var showPrivacySecurity = false
    @State private var showDataBackup = false
    @State private var showSubscription = false
    @State private var showAbout = false

    // Drafts for server edit sheet (kept here so they survive reopen)
    @State private var draftServerURL = ""
    @State private var draftBackupURL = ""

    /// Marketing version pulled from Info.plist (e.g. "1.6.0").
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Subtitle for the Currency row — shows current selection.
    private var currencySubtitle: String {
        let code = CurrencyManager.resolvedCode
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        if vm.state.settings.currencyCode.isEmpty {
            return "Auto · \(name) (\(code))"
        }
        return "\(name) (\(code))"
    }

    /// Subtitle for the Server row — adapts to whether a backup is set.
    private var serverSubtitle: String {
        if backupServerURL.isEmpty { return "Primary URL configured" }
        return "Primary + backup configured"
    }

    private var subscriptionSubtitle: String {
        let pm = PurchaseManager.shared
        if pm.isPurchased { return "\(PurchaseManager.brandName) Pro · Unlocked" }
        if pm.isTrialActive { return "Trial · \(pm.trialDaysRemaining) day\(pm.trialDaysRemaining == 1 ? "" : "s") left" }
        return "Trial expired · Upgrade to unlock"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HexBGView().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        // Inline Appearance picker — single control, no
                        // need for a drilldown sheet
                        AppearancePickerCard(selection: $colorSchemePref)

                        SettingsCategoryRow(
                            icon: "banknote.fill",
                            title: "Currency",
                            subtitle: currencySubtitle,
                            action: { showCurrency = true }
                        )

                        SettingsCategoryRow(
                            icon: "person.2.fill",
                            title: "Household",
                            subtitle: "People, greetings, and pay info",
                            action: { showHousehold = true }
                        )

                        if !vm.isLocal {
                            SettingsCategoryRow(
                                icon: "envelope.fill",
                                title: "Email Relay",
                                subtitle: "SMTP, Mailgun, SendGrid, Resend",
                                action: { showEmailRelay = true }
                            )
                        }

                        if !vm.isLocal {
                            SettingsCategoryRow(
                                icon: "server.rack",
                                title: "Server",
                                subtitle: serverSubtitle,
                                action: {
                                    draftServerURL = serverURL
                                    draftBackupURL = backupServerURL
                                    showServerEdit = true
                                }
                            )
                        }

                        SettingsCategoryRow(
                            icon: "externaldrive.fill",
                            title: "Data & Backup",
                            subtitle: "Export, import, or clear your data",
                            action: { showDataBackup = true }
                        )

                        SettingsCategoryRow(
                            icon: "lock.shield.fill",
                            title: "Privacy & Security",
                            subtitle: AppLockManager.shared.isEnabled ? "App Lock on" : "App Lock off",
                            action: { showPrivacySecurity = true }
                        )

                        SettingsCategoryRow(
                            icon: "lock.open.fill",
                            title: "Subscription",
                            subtitle: subscriptionSubtitle,
                            action: { showSubscription = true }
                        )

                        SettingsCategoryRow(
                            icon: "info.circle.fill",
                            title: "About",
                            subtitle: "Version \(appVersion)",
                            action: { showAbout = true }
                        )

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .refreshable { await vm.refresh() }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCurrency) {
                CurrencySettingsSheet().environmentObject(vm)
            }
            .sheet(isPresented: $showHousehold) {
                HouseholdSettingsSheet().environmentObject(vm)
            }
            .sheet(isPresented: $showEmailRelay) {
                EmailRelaySettingsSheet().environmentObject(vm)
            }
            .sheet(isPresented: $showServerEdit) {
                ServerEditSheet(
                    primaryURL: $draftServerURL,
                    backupURL: $draftBackupURL,
                    onSave: { newPrimary, newBackup in
                        serverURL = newPrimary
                        backupServerURL = newBackup
                        APIClient.shared.serverURL = newPrimary
                        APIClient.shared.backupServerURL = newBackup
                        Task { await vm.load() }
                    },
                    onLogout: {
                        serverURL = ""
                        backupServerURL = ""
                        APIClient.shared.serverURL = ""
                        APIClient.shared.backupServerURL = ""
                    }
                )
            }
            .sheet(isPresented: $showDataBackup) {
                DataBackupSettingsSheet().environmentObject(vm)
            }
            .sheet(isPresented: $showPrivacySecurity) {
                PrivacySecuritySheet()
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionSettingsSheet().environmentObject(vm)
            }
            .sheet(isPresented: $showAbout) {
                AboutSettingsSheet(version: appVersion)
            }
        }
    }
}

// MARK: - Settings Section

/// Reusable card container for a titled settings group.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .bhSectionTitle()
                .padding(.bottom, 2)

            content
        }
        .padding(16)
        .bhCard()
    }
}

// MARK: - Person Card (Expandable)

/// An expandable card for a household member in the Settings people list.
///
/// The collapsed state shows the person's name, color dot, and payment method.
/// Expanding reveals editable fields for name, color, payment method, pay ID,
/// email, and a remove button (non-"me" only).
struct PersonCardView: View {
    @EnvironmentObject var vm: AppViewModel
    let idx: Int
    let person: Person
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header — tappable to expand/collapse
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: person.color) ?? .bhAmber)
                        .frame(width: 12, height: 12)

                    Text(person.name.isEmpty ? "New Person" : person.name)
                        .font(.bhBodySecondary.weight(.semibold))
                        .foregroundColor(.bhText)
                        .lineLimit(1)

                    Spacer()

                    if person.isMe {
                        Text("★ YOU")
                            .font(.caption2.weight(.semibold).monospaced())
                            .foregroundColor(.bhAmber)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.bhAmber.opacity(0.12))
                            .cornerRadius(4)
                    } else {
                        Text(person.payMethod.displayName)
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.bhCaption.weight(.medium))
                        .foregroundColor(.bhMuted)
                        .frame(width: 16)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.bhBorder)
                PersonBodyView(person: person)
            }
        }
        .background(Color.bhSurface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isExpanded ? Color.bhBorder2 : Color.bhBorder, lineWidth: 1)
        )
    }
}

// MARK: - Person Body (Expanded Fields)

/// The expanded body of a person card, containing editable fields.
///
/// Refactored to use `@ViewBuilder` instead of `AnyView` to preserve
/// SwiftUI's type-based diffing performance.
struct PersonBodyView: View {
    @EnvironmentObject var vm: AppViewModel
    let person: Person

    /// Safely looks up the current index each time the body is evaluated,
    /// guarding against stale indices after array mutations.
    private var currentIdx: Int? {
        vm.state.people.firstIndex(where: { $0.id == person.id })
    }

    /// The person's current payment method, resolved via live index lookup.
    private var payMethod: PayMethod {
        guard let idx = currentIdx else { return .none }
        return vm.state.people[idx].payMethod
    }

    var body: some View {
        if currentIdx != nil {
            personFields
        }
    }

    /// All editable fields for this person, extracted to keep the body clean.
    @ViewBuilder
    private var personFields: some View {
        let showPayId = payMethod == .zelle || payMethod == .venmo || payMethod == .cashapp
        let payIdLabel = payMethod == .venmo ? "Venmo Handle" : payMethod == .cashapp ? "Cash Tag" : "Phone / Email"
        let payIdPlaceholder = payMethod == .venmo ? "@handle" : payMethod == .cashapp ? "$cashtag" : "phone or email"

        VStack(alignment: .leading, spacing: 12) {
            // Name + color picker
            PersonFieldRow("Name") {
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: {
                            guard let idx = currentIdx else { return .bhAmber }
                            return Color(hex: vm.state.people[idx].color) ?? .bhAmber
                        },
                        set: { newColor in
                            guard let idx = currentIdx, let hex = newColor.toHex() else { return }
                            vm.state.people[idx].color = hex
                            vm.save()
                        }
                    ))
                    .frame(width: 26, height: 26)
                    .labelsHidden()

                    TextField("Name", text: Binding(
                        get: {
                            guard let idx = currentIdx else { return "" }
                            return vm.state.people[idx].name
                        },
                        set: { newValue in
                            guard let idx = currentIdx else { return }
                            vm.state.people[idx].name = newValue
                            vm.save()
                        }
                    ))
                    .font(.bhBodySecondary)
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.bhSurface2)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
            }

            // Payment method picker
            PersonFieldRow("Payment") {
                Picker("Pay method", selection: Binding(
                    get: { payMethod },
                    set: { newValue in
                        guard let idx = currentIdx else { return }
                        vm.state.people[idx].payMethod = newValue
                        vm.save()
                    }
                )) {
                    ForEach(PayMethod.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .tint(.bhText)
                .font(.bhBodySecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.bhSurface2)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
            }

            // Pay ID (Zelle / Venmo / Cash App)
            if showPayId {
                PersonFieldRow(payIdLabel) {
                    TextField(payIdPlaceholder, text: Binding(
                        get: {
                            guard let idx = currentIdx else { return "" }
                            return vm.state.people[idx].payId
                        },
                        set: { newValue in
                            guard let idx = currentIdx else { return }
                            vm.state.people[idx].payId = newValue
                            vm.save()
                        }
                    ))
                    .font(.bhBodySecondary)
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(payMethod == .zelle ? .phonePad : .default)
                    .padding(8)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
                }
            }

            // Custom Zelle URL
            if payMethod == .zelle {
                PersonFieldRow("Zelle URL") {
                    TextField("Custom URL (optional)", text: Binding(
                        get: {
                            guard let idx = currentIdx else { return "" }
                            return vm.state.people[idx].zelleUrl ?? ""
                        },
                        set: { newValue in
                            guard let idx = currentIdx else { return }
                            let v = newValue.trimmingCharacters(in: .whitespaces)
                            vm.state.people[idx].zelleUrl = v.isEmpty ? nil : v
                            vm.save()
                        }
                    ))
                    .font(.bhBodySecondary)
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(8)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
                }
            }

            // Email
            PersonFieldRow("Email") {
                TextField("Notifications email", text: Binding(
                    get: {
                        guard let idx = currentIdx else { return "" }
                        return vm.state.people[idx].email
                    },
                    set: { newValue in
                        guard let idx = currentIdx else { return }
                        vm.state.people[idx].email = newValue
                        vm.save()
                    }
                ))
                .font(.bhBodySecondary)
                .foregroundColor(.bhText)
                .textFieldStyle(.plain)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(8)
                .background(Color.bhSurface2)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
            }

            // Remove button (non-"me" only)
            if !person.isMe {
                Button {
                    if let idx = currentIdx {
                        vm.removePerson(at: idx)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                        Text("Remove \(person.name.isEmpty ? "Person" : person.name)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BHDangerButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(14)
    }
}

// MARK: - Person Field Row

/// A labeled row used in the person body — title label above the content.
struct PersonFieldRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.medium).monospaced())
                .tracking(1.2)
                .foregroundColor(.bhMuted)
            content
        }
    }
}

// MARK: - Email Config Section

/// Server-side email relay configuration panel.
///
/// Allows the user to select a provider (SMTP, Mailgun, SendGrid, Resend),
/// enter credentials, save, and send a test email.
struct EmailConfigSection: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var config = EmailConfig()
    @State private var isLoading = false
    @State private var isTesting = false
    @State private var statusMsg: String? = nil
    @State private var statusOK = false

    var body: some View {
        SettingsSection(title: "Email Relay") {
            Text("Configure a mail provider so BillHive can send HTML bill summaries. API keys are stored server-side.")
                .font(.bhCaption)
                .foregroundColor(.bhMuted)
                .padding(.bottom, 8)

            // Provider picker
            HStack {
                Text("Provider").font(.bhCaption).foregroundColor(.bhMuted).frame(width: 80, alignment: .leading)
                Picker("", selection: $config.provider) {
                    ForEach(EmailProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(.bhText)
            }

            EMField("From Name", value: $config.fromName, placeholder: "e.g. Marty")
            EMField("From Email", value: $config.fromEmail, placeholder: "you@domain.com", keyboard: .emailAddress)

            // Provider-specific fields
            let provider = EmailProvider(rawValue: config.provider) ?? .disabled
            switch provider {
            case .smtp:
                EMField("SMTP Host", value: Binding(get: { config.smtpHost ?? "" }, set: { config.smtpHost = $0 }), placeholder: "smtp.gmail.com")
                EMField("SMTP Port", value: Binding(get: { config.smtpPort ?? "" }, set: { config.smtpPort = $0 }), placeholder: "587", keyboard: .numberPad)
                EMField("Username", value: Binding(get: { config.smtpUser ?? "" }, set: { config.smtpUser = $0 }), placeholder: "your@gmail.com")
                EMField("Password", value: Binding(get: { config.smtpPass ?? "" }, set: { config.smtpPass = $0 }), placeholder: "App password", isSecure: true)
            case .mailgun:
                EMField("API Key", value: Binding(get: { config.mailgunApiKey ?? "" }, set: { config.mailgunApiKey = $0 }), placeholder: "key-••••", isSecure: true)
                EMField("Domain", value: Binding(get: { config.mailgunDomain ?? "" }, set: { config.mailgunDomain = $0 }), placeholder: "mg.yourdomain.com")
            case .sendgrid:
                EMField("API Key", value: Binding(get: { config.sendgridApiKey ?? "" }, set: { config.sendgridApiKey = $0 }), placeholder: "SG.••••", isSecure: true)
            case .resend:
                EMField("API Key", value: Binding(get: { config.resendApiKey ?? "" }, set: { config.resendApiKey = $0 }), placeholder: "re_••••", isSecure: true)
            case .disabled:
                EmptyView()
            }

            // Status message
            if let msg = statusMsg {
                HStack(spacing: 6) {
                    Image(systemName: statusOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(statusOK ? .bhAmber : .bhRed)
                    Text(msg).font(.bhCaption).foregroundColor(statusOK ? .bhAmber : .bhRed)
                }
            }

            // Action buttons
            HStack(spacing: 10) {
                Button("Save") {
                    Task { await saveConfig() }
                }
                .buttonStyle(BHPrimaryButtonStyle())

                Button {
                    Task { await testConfig() }
                } label: {
                    HStack {
                        if isTesting { ProgressView().tint(.bhText).scaleEffect(0.7) }
                        Text(isTesting ? "Sending..." : "Send Test")
                    }
                }
                .buttonStyle(BHSecondaryButtonStyle())
                .disabled(isTesting)
            }
        }
        .task { await loadConfig() }
    }

    // MARK: - Email Config Actions

    private func loadConfig() async {
        isLoading = true
        if let cfg = try? await APIClient.shared.getEmailConfig() {
            config = cfg
        }
        isLoading = false
    }

    private func saveConfig() async {
        do {
            try await APIClient.shared.saveEmailConfig(config)
            statusOK = true; statusMsg = "Saved!"
        } catch {
            statusOK = false; statusMsg = error.localizedDescription
        }
    }

    private func testConfig() async {
        isTesting = true
        do {
            let msg = try await APIClient.shared.testEmail()
            statusOK = true; statusMsg = msg
        } catch {
            statusOK = false; statusMsg = error.localizedDescription
        }
        isTesting = false
    }
}

// MARK: - Email Field Row

/// A horizontal label + text field row used in the email config section.
struct EMField: View {
    let label: String
    @Binding var value: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false

    init(_ label: String, value: Binding<String>, placeholder: String = "", keyboard: UIKeyboardType = .default, isSecure: Bool = false) {
        self.label = label
        self._value = value
        self.placeholder = placeholder
        self.keyboard = keyboard
        self.isSecure = isSecure
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.bhCaption)
                .foregroundColor(.bhMuted)
                .frame(width: 80, alignment: .leading)

            if isSecure {
                SecureField(placeholder, text: $value)
                    .font(.bhCaption)
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .padding(7)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
            } else {
                TextField(placeholder, text: $value)
                    .font(.bhCaption)
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .keyboardType(keyboard)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(7)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
            }
        }
    }
}

// MARK: - Server Row

/// A read-only row in the Settings server section, showing one configured
/// URL and whether it's currently the active (last-known-good) server.
struct ServerRow: View {
    let label: String
    let url: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.bhCaption.weight(.semibold))
                    .foregroundColor(.bhText)
                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.bhAmber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.bhAmber.opacity(0.15))
                        .cornerRadius(3)
                }
                Spacer()
            }
            Text(url)
                .font(.bhCaption)
                .foregroundColor(.bhMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Server Edit Sheet

/// Modal sheet for editing the primary and (optional) backup server URLs.
/// Each field has its own Test button to verify reachability before save.
struct ServerEditSheet: View {
    @Binding var primaryURL: String
    @Binding var backupURL: String
    let onSave: (_ primary: String, _ backup: String) -> Void
    let onLogout: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var isTestingPrimary = false
    @State private var primaryResult: String? = nil
    @State private var primarySuccess = false

    @State private var isTestingBackup = false
    @State private var backupResult: String? = nil
    @State private var backupSuccess = false

    // API key — pre-populated from Keychain so the user can see/edit/clear it.
    @State private var apiKey: String = APIClient.shared.apiKey

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: Connection Section
                        SettingsSection(title: "Connection") {
                            urlField(
                                title: "Primary Server URL",
                                placeholder: "http://192.168.1.100:8080",
                                text: $primaryURL,
                                result: primaryResult,
                                success: primarySuccess,
                                isTesting: isTestingPrimary,
                                onTest: { Task { await test(primary: true) } }
                            )

                            Divider().background(Color.bhBorder)

                            urlField(
                                title: "Backup Server URL (optional)",
                                placeholder: "http://100.x.y.z:8080",
                                text: $backupURL,
                                result: backupResult,
                                success: backupSuccess,
                                isTesting: isTestingBackup,
                                onTest: { Task { await test(primary: false) } }
                            )

                            Text("The app will use the primary server when reachable and automatically fall back to the backup otherwise.")
                                .font(.bhCaption)
                                .foregroundColor(.bhMuted)
                                .multilineTextAlignment(.leading)
                                .padding(.top, 4)
                        }

                        // MARK: API Key Section
                        SettingsSection(title: "API Key") {
                            apiKeyContent
                        }

                        // MARK: Actions
                        Button {
                            APIClient.shared.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSave(primaryURL, backupURL)
                            dismiss()
                        } label: {
                            Text("Save & Reconnect")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BHPrimaryButtonStyle())
                        .disabled(primaryURL.isEmpty)

                        Button {
                            onLogout()
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Logout")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BHDangerButtonStyle())

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.bhAmber)
                }
            }
        }
        .bhColorScheme()
    }

    // API key content — SecureField pre-populated from Keychain. Empty value
    // on save clears the stored key. Connection tests include the entered
    // key (not the saved one) so the user can verify a new key before
    // committing.
    @ViewBuilder
    private var apiKeyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Optional")
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)
                Spacer()
                if !apiKey.isEmpty {
                    Button {
                        apiKey = ""
                    } label: {
                        Text("Clear")
                            .font(.bhCaption)
                            .foregroundColor(.bhRed)
                    }
                }
            }

            SecureField("bh_live_…", text: $apiKey)
                .font(.bhBodySecondary)
                .foregroundColor(.bhText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.bhSurface2)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Text("Generate one in BillHive web → Settings → Connected Devices. Stored in iOS Keychain, not iCloud.")
                .font(.bhCaption)
                .foregroundColor(.bhMuted)
        }
    }

    @ViewBuilder
    private func urlField(title: String,
                          placeholder: String,
                          text: Binding<String>,
                          result: String?,
                          success: Bool,
                          isTesting: Bool,
                          onTest: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .bhSectionTitle()

            TextField(placeholder, text: text)
                .font(.bhBodySecondary)
                .foregroundColor(.bhText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.bhSurface2)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)

            if let result {
                HStack(spacing: 6) {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(success ? .bhAmber : .bhRed)
                    Text(result)
                        .font(.bhCaption)
                        .foregroundColor(success ? .bhAmber : .bhRed)
                    Spacer()
                }
            }

            Button(action: onTest) {
                HStack {
                    if isTesting {
                        ProgressView().tint(.bhText).scaleEffect(0.7)
                    }
                    Text(isTesting ? "Testing..." : "Test Connection")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(BHSecondaryButtonStyle())
            .disabled(text.wrappedValue.isEmpty || isTesting)
        }
    }

    private func test(primary: Bool) async {
        if primary {
            isTestingPrimary = true
            primaryResult = nil
            let r = await APIClient.testConnection(rawURL: primaryURL, apiKey: apiKey)
            primarySuccess = r.success
            primaryResult = r.message
            isTestingPrimary = false
        } else {
            isTestingBackup = true
            backupResult = nil
            let r = await APIClient.testConnection(rawURL: backupURL, apiKey: apiKey)
            backupSuccess = r.success
            backupResult = r.message
            isTestingBackup = false
        }
    }
}

// MARK: - Purchase Settings Section

/// Shows trial status, purchase button, and restore link in Settings.
struct PurchaseSettingsSection: View {
    @ObservedObject var pm = PurchaseManager.shared
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        if pm.isPurchased {
            // Full-width banner when purchased, with a Restore link for users
            // who reinstall or change devices and need to re-fetch their entitlement.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.bhAmber)
                        .font(.subheadline)
                    Text("\(PurchaseManager.brandName) Pro")
                        .font(.bhBodyName.weight(.semibold))
                        .foregroundColor(.bhAmber)
                    Spacer()
                    Button {
                        Task { await pm.restore() }
                    } label: {
                        Text("Restore")
                            .font(.bhCaption.weight(.semibold))
                            .foregroundColor(.bhAmber)
                    }
                    .accessibilityHint("Re-fetch your purchase from the App Store")
                }
                if let error = pm.errorMessage {
                    Text(error)
                        .font(.bhCaption)
                        .foregroundColor(.bhRed)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.bhSurface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bhBorder, lineWidth: 1))
        } else {
            // Full card when not purchased
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(.bhMuted)
                        .font(.subheadline)
                    Text(pm.trialStatusText)
                        .font(.bhBodySecondary)
                        .foregroundColor(.bhText)
                }

                if pm.isTrialActive {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.bhSurface2)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(trialBarColor)
                                .frame(width: geo.size.width * CGFloat(pm.trialDaysRemaining) / CGFloat(PurchaseManager.trialDays), height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                Button {
                    vm.presentPaywall()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .font(.caption)
                        Text(pm.unlockButtonLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BHPrimaryButtonStyle())

                Button {
                    Task { await pm.restore() }
                } label: {
                    Text("Restore Previous Purchase")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)
                }

                if let error = pm.errorMessage {
                    Text(error)
                        .font(.bhCaption)
                        .foregroundColor(.bhRed)
                }
            }
            .padding(14)
            .bhCard()
        }
    }

    /// Trial bar color — green when full, amber midway, red when almost expired.
    private var trialBarColor: Color {
        let fraction = Double(pm.trialDaysRemaining) / Double(PurchaseManager.trialDays)
        if fraction > 0.5 {
            return Color(red: 0.2, green: 0.8, blue: 0.3)
        } else if fraction > 0.25 {
            return .bhAmber
        } else {
            return .bhRed
        }
    }
}

// MARK: - Settings Category Row

/// A tappable row in the top-level Settings list. Shows an amber-tinted
/// circular icon, a title, a subtitle, and a trailing chevron.
struct SettingsCategoryRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.bhAmber.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundColor(.bhAmber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.bhBodyName)
                        .foregroundColor(.bhText)
                    Text(subtitle)
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.bhMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(Color.bhSurface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bhBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}


// Settings sheet views (CurrencySettingsSheet, HouseholdSettingsSheet, EmailRelaySettingsSheet,
// DataBackupSettingsSheet, SubscriptionSettingsSheet, AboutSettingsSheet) are defined in SettingsSheets.swift

// MARK: - Appearance Picker Card

/// Inline card on the Settings root with a 3-way segmented control for
/// color scheme: System / Light / Dark. The selection is bound to the
/// `colorSchemePref` AppStorage key, which `.bhColorScheme()` reads from
/// every view that needs to enforce a scheme.
struct AppearancePickerCard: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.bhAmber.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "circle.lefthalf.filled")
                    .font(.subheadline)
                    .foregroundColor(.bhAmber)
            }

            Text("Appearance")
                .font(.bhBodyName)
                .foregroundColor(.bhText)

            Spacer()

            Picker("Appearance", selection: $selection) {
                ForEach(ColorSchemePreference.allCases) { pref in
                    Text(pref.label).tag(pref.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.bhSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bhBorder, lineWidth: 1))
    }
}
