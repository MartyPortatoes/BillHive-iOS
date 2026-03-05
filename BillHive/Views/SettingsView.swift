import SwiftUI

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
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.bhText)
                            .padding(.top, 16)

                        // People
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

                        // Email Greetings
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

                        // Email Relay (server-only)
                        if !vm.isLocal {
                            EmailConfigSection()
                        }

                        // Data
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

                        // Server (server-only)
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
                })
            }
        }
    }
}

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

// ── Person expandable card (mirrors BillCardView pattern) ────────────────────
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
                PersonBodyView(idx: idx, person: person)
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

struct PersonBodyView: View {
    @EnvironmentObject var vm: AppViewModel
    let idx: Int
    let person: Person

    var body: some View {
        // Get current index safely
        guard let currentIdx = vm.state.people.firstIndex(where: { $0.id == person.id }) else {
            return AnyView(EmptyView())
        }
        
        let pm = vm.state.people[currentIdx].payMethod
        let showPayId = pm == .zelle || pm == .venmo || pm == .cashapp
        let payIdLabel = pm == .venmo ? "Venmo Handle" : pm == .cashapp ? "Cash Tag" : "Phone / Email"
        let payIdPlaceholder = pm == .venmo ? "@handle" : pm == .cashapp ? "$cashtag" : "phone or email"

        return AnyView(VStack(alignment: .leading, spacing: 12) {
            // Name + color picker
            PersonFieldRow("Name") {
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: {
                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                return Color(hex: vm.state.people[idx].color) ?? .bhAmber
                            }
                            return .bhAmber
                        },
                        set: { newColor in
                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }),
                               let hex = newColor.toHex() {
                                vm.state.people[idx].color = hex
                                vm.save()
                            }
                        }
                    ))
                    .frame(width: 26, height: 26)
                    .labelsHidden()

                    TextField("Name", text: Binding(
                        get: {
                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                return vm.state.people[idx].name
                            }
                            return ""
                        },
                        set: { newValue in
                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                vm.state.people[idx].name = newValue
                                vm.save()
                            }
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

            // Payment method — full width so labels never wrap
            PersonFieldRow("Payment") {
                Picker("Pay method", selection: Binding(
                    get: {
                        if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                            return vm.state.people[idx].payMethod
                        }
                        return .none
                    },
                    set: { newValue in
                        if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                            vm.state.people[idx].payMethod = newValue
                            vm.save()
                        }
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
                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                return vm.state.people[idx].payId
                            }
                            return ""
                        },
                        set: { newValue in
                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                vm.state.people[idx].payId = newValue
                                vm.save()
                            }
                        }
                    ))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(pm == .zelle ? .phonePad : .default)
                    .padding(8)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
                }
            }

            // Custom Zelle URL
            if pm == .zelle {
                PersonFieldRow("Zelle URL") {
                    TextField("Custom URL (optional)", text: Binding(
                        get: {
                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                return vm.state.people[idx].zelleUrl ?? ""
                            }
                            return ""
                        },
                        set: { newValue in
                            if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                let v = newValue.trimmingCharacters(in: .whitespaces)
                                vm.state.people[idx].zelleUrl = v.isEmpty ? nil : v
                                vm.save()
                            }
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
                        if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                            return vm.state.people[idx].email
                        }
                        return ""
                    },
                    set: { newValue in
                        if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                            vm.state.people[idx].email = newValue
                            vm.save()
                        }
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

            // Remove (non-me only)
            if !person.isMe {
                Button {
                    if let idx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
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
        .padding(14))
    }
}

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

            // Provider
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

            if let msg = statusMsg {
                HStack(spacing: 6) {
                    Image(systemName: statusOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(statusOK ? .bhAmber : .bhRed)
                    Text(msg).font(.system(size: 11, design: .monospaced)).foregroundColor(statusOK ? .bhAmber : .bhRed)
                }
            }

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

    func loadConfig() async {
        isLoading = true
        if let cfg = try? await APIClient.shared.getEmailConfig() {
            config = cfg
        }
        isLoading = false
    }

    func saveConfig() async {
        do {
            try await APIClient.shared.saveEmailConfig(config)
            statusOK = true; statusMsg = "Saved!"
        } catch {
            statusOK = false; statusMsg = error.localizedDescription
        }
    }

    func testConfig() async {
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

struct ServerEditSheet: View {
    @Binding var url: String
    let onSave: (String) -> Void
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
                    Spacer()
                }
                .padding(24)
            }
            .navigationBarHidden(true)
        }
    }
}

extension Color {
    func toHex() -> String? {
        let uic = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uic.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
