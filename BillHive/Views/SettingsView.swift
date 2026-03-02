import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: AppViewModel
    @AppStorage("serverURL") private var serverURL: String = ""
    @State private var showImportPicker = false
    @State private var showClearConfirm = false
    @State private var showServerEdit = false
    @State private var draftServerURL = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Settings")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.bhText)
                            .padding(.top, 16)

                        // People
                        SettingsSection(title: "People") {
                            VStack(spacing: 0) {
                                ForEach(Array(vm.state.people.enumerated()), id: \.element.id) { idx, person in
                                    PersonRowView(idx: idx, person: person)
                                    if idx < vm.state.people.count - 1 {
                                        Divider().background(Color.bhBorder).padding(.vertical, 2)
                                    }
                                }
                            }

                            Button {
                                vm.addPerson()
                            } label: {
                                Label("Add Person", systemImage: "plus")
                                    .font(.system(size: 11, design: .monospaced))
                            }
                            .buttonStyle(BHSecondaryButtonStyle())
                            .padding(.top, 12)
                        }

                        // Email Greetings
                        SettingsSection(title: "Email Greetings") {
                            Text("Custom opening line for each person's bill email")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.bhMuted)
                                .padding(.bottom, 8)

                            ForEach(Array(vm.state.people.filter { $0.id != "me" }.enumerated()), id: \.element.id) { _, person in
                                if let globalIdx = vm.state.people.firstIndex(where: { $0.id == person.id }) {
                                    HStack(spacing: 8) {
                                        Circle().fill(Color(hex: person.color) ?? .bhAmber).frame(width: 8, height: 8)
                                        Text(person.name)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.bhText)
                                            .frame(width: 80, alignment: .leading)
                                        TextField("Hey \(person.name),", text: Binding(
                                            get: { vm.state.people[globalIdx].greeting },
                                            set: { vm.state.people[globalIdx].greeting = $0; vm.save() }
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
                        }

                        // Email Relay (server-only)
                        if !vm.isLocal {
                            EmailConfigSection()
                        }

                        // Bill Config
                        SettingsSection(title: "Bills") {
                            ForEach(Array(vm.state.bills.enumerated()), id: \.element.id) { idx, bill in
                                HStack(spacing: 8) {
                                    TextField("", text: Binding(
                                        get: { vm.state.bills[idx].icon },
                                        set: { vm.state.bills[idx].icon = $0; vm.save() }
                                    ))
                                    .font(.system(size: 18))
                                    .multilineTextAlignment(.center)
                                    .frame(width: 36, height: 36)
                                    .background(Color.bhSurface2)
                                    .cornerRadius(6)

                                    TextField("Bill name", text: Binding(
                                        get: { vm.state.bills[idx].name },
                                        set: { vm.state.bills[idx].name = $0; vm.save() }
                                    ))
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.bhText)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .background(Color.bhSurface2)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))

                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: vm.state.bills[idx].color) ?? .bhAmber },
                                        set: { newColor in
                                            if let hex = newColor.toHex() {
                                                vm.state.bills[idx].color = hex
                                                vm.save()
                                            }
                                        }
                                    ))
                                    .frame(width: 36, height: 36)
                                    .labelsHidden()

                                    Button {
                                        vm.removeBill(bill)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10))
                                            .foregroundColor(.bhRed)
                                            .frame(width: 28, height: 28)
                                            .background(Color.bhSurface2)
                                            .cornerRadius(5)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.bhRed.opacity(0.5), lineWidth: 1))
                                    }
                                }
                                .padding(.vertical, 4)
                                if idx < vm.state.bills.count - 1 {
                                    Divider().background(Color.bhBorder)
                                }
                            }
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

struct PersonRowView: View {
    @EnvironmentObject var vm: AppViewModel
    let idx: Int
    let person: Person

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Name row
            HStack(spacing: 8) {
                ColorPicker("", selection: Binding(
                    get: { Color(hex: vm.state.people[idx].color) ?? .bhAmber },
                    set: { newColor in
                        if let hex = newColor.toHex() {
                            vm.state.people[idx].color = hex
                            vm.save()
                        }
                    }
                ))
                .frame(width: 28, height: 28)
                .labelsHidden()

                TextField("Name", text: Binding(
                    get: { vm.state.people[idx].name },
                    set: { vm.state.people[idx].name = $0; vm.save() }
                ))
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.bhText)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.bhSurface2)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))

                if !person.isMe {
                    Button {
                        vm.removePerson(at: idx)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.bhRed)
                            .frame(width: 24, height: 24)
                            .background(Color.bhSurface2)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.bhRed.opacity(0.5), lineWidth: 1))
                    }
                } else {
                    Text("you")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.bhMuted2)
                        .frame(width: 24)
                }
            }

            // Payment method + ID row
            HStack(spacing: 8) {
                Picker("Pay method", selection: Binding(
                    get: { vm.state.people[idx].payMethod },
                    set: { vm.state.people[idx].payMethod = $0; vm.save() }
                )) {
                    ForEach(PayMethod.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .tint(.bhText)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 115)
                .padding(6)
                .background(Color.bhSurface2)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))

                let pm = vm.state.people[idx].payMethod
                if pm != .none && pm != .manual {
                    TextField(
                        pm == .venmo ? "@handle" : pm == .cashapp ? "$cashtag" : "phone / email",
                        text: Binding(
                            get: { vm.state.people[idx].payId },
                            set: { vm.state.people[idx].payId = $0; vm.save() }
                        )
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .padding(7)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                }
            }

            // Custom Zelle URL (only when Zelle is selected)
            if vm.state.people[idx].payMethod == .zelle {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundColor(.bhMuted)
                        .frame(width: 16)

                    TextField("Custom Zelle URL (optional)", text: Binding(
                        get: { vm.state.people[idx].zelleUrl ?? "" },
                        set: {
                            let v = $0.trimmingCharacters(in: .whitespaces)
                            vm.state.people[idx].zelleUrl = v.isEmpty ? nil : v
                            vm.save()
                        }
                    ))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(7)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
                }
            }

            // Email row
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .font(.system(size: 11))
                    .foregroundColor(.bhMuted)
                    .frame(width: 16)

                TextField("Email for notifications", text: Binding(
                    get: { vm.state.people[idx].email },
                    set: { vm.state.people[idx].email = $0; vm.save() }
                ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.bhText)
                .textFieldStyle(.plain)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(7)
                .background(Color.bhSurface2)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))
            }
        }
        .padding(.vertical, 8)
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
                Color.bhBackground.ignoresSafeArea()
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
