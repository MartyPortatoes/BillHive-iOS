import SwiftUI

// MARK: - Settings View

/// Top-level settings screen with people management, email greetings,
/// email relay configuration (server-only), data export/import, and server URL.
struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @AppStorage("serverURL") private var serverURL: String = ""
    @State private var showImportPicker = false
    @State private var showClearConfirm = false
    @State private var showServerEdit = false
    @State private var draftServerURL = ""
    @State private var expandedPersonId: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                HexBGView().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Settings")
                            .font(.system(size: 18, weight: .bold, design: .default))
                            .foregroundColor(.bhText)
                            .padding(.top, 16)

                        // MARK: Purchase Section

                        #if BILLHIVE_LOCAL
                        PurchaseSettingsSection()
                        #endif

                        // MARK: People Section

                        VStack(alignment: .leading, spacing: 8) {
                            Text("People")
                                .bhSectionTitle()
                                .padding(.bottom, 2)

                            // Explanatory note about the primary person
                            (Text("The ").font(.system(size: 11, design: .monospaced)).foregroundColor(.bhMuted)
                            + Text("★ Primary").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.bhAmber)
                            + Text(" person is ").font(.system(size: 11, design: .monospaced)).foregroundColor(.bhMuted)
                            + Text("you").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(.bhText)
                            + Text(" — the one who fronts all bills and collects from everyone else. This person cannot be removed.").font(.system(size: 11, design: .monospaced)).foregroundColor(.bhMuted))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)

                            ForEach(Array(vm.state.people.enumerated()), id: \.element.id) { idx, person in
                                PersonCardView(
                                    idx: idx,
                                    person: person,
                                    isExpanded: expandedPersonId == person.id,
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedPersonId = expandedPersonId == person.id ? nil : person.id
                                        }
                                    }
                                )
                            }

                            Button {
                                vm.addPerson()
                                if let last = vm.state.people.last {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        expandedPersonId = last.id
                                    }
                                }
                            } label: {
                                Label("Add Person", systemImage: "plus")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .buttonStyle(BHSecondaryButtonStyle())
                        }

                        // MARK: Email Greetings Section

                        SettingsSection(title: "Email Greetings") {
                            Text("Custom opening line for each person's bill email")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.bhMuted)
                                .padding(.bottom, 8)

                            ForEach(vm.state.people.filter { $0.id != "me" }) { person in
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hex: person.color) ?? .bhAmber).frame(width: 8, height: 8)
                                    Text(person.name)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.bhText)
                                        .frame(width: 80, alignment: .leading)
                                    TextField("Hey \(person.name),", text: Binding(
                                        get: {
                                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                                return vm.state.people[idx].greeting
                                            }
                                            return ""
                                        },
                                        set: { newValue in
                                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                                vm.state.people[idx].greeting = newValue
                                                vm.save()
                                            }
                                        }
                                    ))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.bhText)
                                    .textFieldStyle(.plain)
                                    .padding(7)
                                    .background(Color.bhSurface2)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        // MARK: Email Relay Section (server-only)

                        if !vm.isLocal {
                            EmailConfigSection()
                        }

                        // MARK: Data Section

                        SettingsSection(title: "Data") {
                            VStack(spacing: 10) {
                                if let exportURL = APIClient.shared.exportURL() {
                                    Link(destination: exportURL) {
                                        HStack {
                                            Image(systemName: "arrow.down.circle")
                                            Text("Export Backup")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(BHSecondaryButtonStyle())
                                }

                                Button {
                                    showClearConfirm = true
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Clear All Data")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(BHDangerButtonStyle())
                            }
                        }

                        // MARK: Server Section (server-only)

                        if !vm.isLocal {
                            SettingsSection(title: "Server") {
                                HStack {
                                    Text(serverURL)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.bhMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("Change") {
                                        draftServerURL = serverURL
                                        showServerEdit = true
                                    }
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.bhAmber)
                                }
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                }
                .refreshable { await vm.refresh() }
            }
            .navigationBarHidden(true)
            .confirmationDialog("Clear all data?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Reset All Data", role: .destructive) {
                    Task {
                        try? await APIClient.shared.saveState(AppState())
                        await vm.load()
                        vm.toast("Data cleared")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all bills, people, and monthly data. This cannot be undone.")
            }
            .sheet(isPresented: $showServerEdit) {
                ServerEditSheet(url: $draftServerURL, onSave: { newURL in
                    serverURL = newURL
                    APIClient.shared.serverURL = newURL
                    Task { await vm.load() }
                }, onLogout: {
                    serverURL = ""
                    APIClient.shared.serverURL = ""
                })
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
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.bhText)
                        .lineLimit(1)

                    Spacer()

                    if person.isMe {
                        Text("★ YOU")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.bhAmber)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.bhAmber.opacity(0.12))
                            .cornerRadius(4)
                    } else {
                        Text(person.payMethod.displayName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.bhMuted)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 12, design: .monospaced))
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
                .font(.system(size: 12, design: .monospaced))
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
                    .font(.system(size: 12, design: .monospaced))
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
                    .font(.system(size: 12, design: .monospaced))
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
                .font(.system(size: 12, design: .monospaced))
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
                .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.bhMuted)
                .padding(.bottom, 8)

            // Provider picker
            HStack {
                Text("Provider").font(.system(size: 11, design: .monospaced)).foregroundColor(.bhMuted).frame(width: 80, alignment: .leading)
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
                    Text(msg).font(.system(size: 11, design: .monospaced)).foregroundColor(statusOK ? .bhAmber : .bhRed)
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
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.bhMuted)
                .frame(width: 80, alignment: .leading)

            if isSecure {
                SecureField(placeholder, text: $value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .padding(7)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
            } else {
                TextField(placeholder, text: $value)
                    .font(.system(size: 11, design: .monospaced))
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

// MARK: - Server Edit Sheet

/// Modal sheet for changing the server URL or logging out.
struct ServerEditSheet: View {
    @Binding var url: String
    let onSave: (String) -> Void
    let onLogout: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HexBGView().ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Change Server URL")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.bhText)

                    TextField("http://192.168.1.100:8080", text: $url)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.bhText)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.bhSurface2)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    HStack(spacing: 12) {
                        Button("Cancel") { dismiss() }.buttonStyle(BHSecondaryButtonStyle())
                        Button("Save & Reconnect") {
                            onSave(url)
                            dismiss()
                        }.buttonStyle(BHPrimaryButtonStyle())
                    }

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

                    Spacer()
                }
                .padding(24)
            }
            .navigationBarHidden(true)
        }
    }
}

#if BILLHIVE_LOCAL
// MARK: - Purchase Settings Section

/// Shows trial status, purchase button, and restore link in Settings.
struct PurchaseSettingsSection: View {
    @ObservedObject var pm = PurchaseManager.shared
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        if pm.isPurchased {
            // Thin full-width banner when purchased
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.bhAmber)
                    .font(.system(size: 13))
                Text("BillHive Pro")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.bhAmber)
                Spacer()
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
                        .font(.system(size: 13))
                    Text(pm.trialStatusText)
                        .font(.system(size: 12, design: .monospaced))
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
                            .font(.system(size: 11))
                        Text("Unlock BillHive — \(pm.priceText)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BHPrimaryButtonStyle())

                Button {
                    Task { await pm.restore() }
                } label: {
                    Text("Restore Previous Purchase")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.bhMuted)
                }

                if let error = pm.errorMessage {
                    Text(error)
                        .font(.system(size: 10, design: .monospaced))
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
#endif

// MARK: - Color → Hex Conversion

extension Color {
    /// Converts a SwiftUI Color to a hex string (e.g. "#FF8800").
    ///
    /// Uses UIColor for component extraction. Returns `nil` if the color
    /// space conversion fails.
    func toHex() -> String? {
        let uic = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uic.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
