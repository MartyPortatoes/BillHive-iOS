import SwiftUI

// MARK: - Currency Settings Sheet

/// Searchable currency picker presented from Settings -> Currency.
/// Shows an "Auto" option (device locale), popular currencies, then the full ISO list.
struct CurrencySettingsSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private static let popular = ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "CHF", "CNY", "INR", "MXN", "BRL", "KRW", "SGD", "HKD", "NZD", "SEK", "NOK", "DKK"]

    private var allCodes: [String] {
        Locale.commonISOCurrencyCodes.sorted()
    }

    private func displayName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    private func matches(_ code: String) -> Bool {
        if search.isEmpty { return true }
        let q = search.lowercased()
        return code.lowercased().contains(q) || displayName(code).lowercased().contains(q)
    }

    private var filteredPopular: [String] {
        Self.popular.filter { matches($0) }
    }

    private var filteredAll: [String] {
        allCodes.filter { !Self.popular.contains($0) && matches($0) }
    }

    private var selected: String { vm.state.settings.currencyCode }

    private var autoLabel: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        let name = displayName(code)
        return "\(name) (\(code))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Search bar
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.bhMuted)
                                .font(.bhCaption)
                            TextField("Search currencies", text: $search)
                                .font(.bhBodySecondary)
                                .foregroundColor(.bhText)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                            if !search.isEmpty {
                                Button { search = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.bhMuted)
                                        .font(.bhCaption)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.bhSurface2)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))

                        // Auto option
                        if search.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AUTOMATIC")
                                    .font(.caption2.weight(.medium).monospaced())
                                    .tracking(1.2)
                                    .foregroundColor(.bhMuted)

                                currencyRow(code: "", label: "Auto", detail: autoLabel, isSelected: selected.isEmpty)
                            }
                        }

                        // Popular currencies
                        if !filteredPopular.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("POPULAR")
                                    .font(.caption2.weight(.medium).monospaced())
                                    .tracking(1.2)
                                    .foregroundColor(.bhMuted)

                                ForEach(filteredPopular, id: \.self) { code in
                                    currencyRow(code: code, label: "\(displayName(code))", detail: code, isSelected: selected == code)
                                }
                            }
                        }

                        // All other currencies
                        if !filteredAll.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ALL CURRENCIES")
                                    .font(.caption2.weight(.medium).monospaced())
                                    .tracking(1.2)
                                    .foregroundColor(.bhMuted)

                                ForEach(filteredAll, id: \.self) { code in
                                    currencyRow(code: code, label: "\(displayName(code))", detail: code, isSelected: selected == code)
                                }
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.bhAmber)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.bhAmber)
                }
            }
        }
        .bhColorScheme()
    }

    @ViewBuilder
    private func currencyRow(code: String, label: String, detail: String, isSelected: Bool) -> some View {
        Button {
            vm.state.settings.currencyCode = code
            CurrencyManager.currencyCode = code
            vm.save()
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.bhBodySecondary.weight(.medium))
                    .foregroundColor(.bhText)
                Spacer()
                Text(detail)
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.bhAmber)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(isSelected ? Color.bhAmber.opacity(0.08) : Color.bhSurface)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.bhAmber.opacity(0.3) : Color.bhBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Household Settings Sheet

/// Combined people management + email greetings, presented as a full-screen
/// sheet from the Settings -> Household row.
struct HouseholdSettingsSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var expandedPersonId: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // People
                        VStack(alignment: .leading, spacing: 8) {
                            Text("People")
                                .bhSectionTitle()
                                .padding(.bottom, 2)

                            (Text("The ").font(.bhCaption).foregroundColor(.bhMuted)
                             + Text("★ Primary").font(.bhCaption.weight(.semibold)).foregroundColor(.bhAmber)
                             + Text(" person is ").font(.bhCaption).foregroundColor(.bhMuted)
                             + Text("you").font(.bhCaption.weight(.bold)).foregroundColor(.bhText)
                             + Text(" — the one who fronts all bills and collects from everyone else. This person cannot be removed.").font(.bhCaption).foregroundColor(.bhMuted))
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
                                    withAnimation { expandedPersonId = last.id }
                                }
                            } label: {
                                Label("Add Person", systemImage: "plus")
                                    .font(.bhCaption)
                            }
                            .buttonStyle(BHSecondaryButtonStyle())
                        }

                        // Greetings
                        SettingsSection(title: "Email Greetings") {
                            Text("Custom opening line for each person's bill email.")
                                .font(.bhCaption)
                                .foregroundColor(.bhMuted)
                                .padding(.bottom, 8)

                            ForEach(vm.state.people.filter { $0.id != "me" }) { person in
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hex: person.color) ?? .bhAmber).frame(width: 8, height: 8)
                                    Text(person.name)
                                        .font(.bhCaption)
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
                                    .font(.bhCaption)
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

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.bhAmber)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.bhAmber)
                }
            }
        }
        .bhColorScheme()
    }
}

// MARK: - Email Relay Settings Sheet

/// Wraps the existing `EmailConfigSection` in a full-screen sheet from
/// Settings -> Email Relay (SelfHive only).
struct EmailRelaySettingsSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    EmailConfigSection()
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Email Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.bhAmber)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.bhAmber)
                }
            }
        }
        .bhColorScheme()
    }
}

// MARK: - Data & Backup Settings Sheet

/// Export and clear-all in a focused full-screen sheet. Behavior adapts
/// to the target:
///
/// - **BillHive (local / iCloud):** Builds a JSON snapshot from in-memory
///   state + monthly data and shares it via `ShareLink`, letting the user
///   save to Files, send via Mail, etc. iCloud sync is the primary backup
///   for this target — the export is an offline insurance copy.
/// - **SelfHive (remote server):** Links directly to the server's
///   `/api/export` endpoint, which streams a JSON download.
struct DataBackupSettingsSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false
    @State private var backupFileURL: URL? = nil
    @State private var backupBuildError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        backupSection
                        dangerSection
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Data & Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.bhAmber)
                }
            }
            .confirmationDialog("Clear all data?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Reset All Data", role: .destructive) {
                    Task {
                        await vm.clearAllData()
                        vm.toast("Data cleared")
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all bills, people, and monthly data. This cannot be undone.")
            }
            .onAppear {
                if vm.isLocal { rebuildBackupFile() }
            }
        }
        .bhColorScheme()
    }

    // MARK: - Backup Section

    @ViewBuilder
    private var backupSection: some View {
        SettingsSection(title: "Backup") {
            if vm.isLocal {
                Text("Your data is automatically synced across your devices via iCloud. Use this to save an offline copy of all bills, people, and monthly data.")
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)
                    .padding(.bottom, 8)

                if let url = backupFileURL {
                    ShareLink(item: url) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Backup")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BHSecondaryButtonStyle())
                } else if let err = backupBuildError {
                    Text(err)
                        .font(.bhCaption)
                        .foregroundColor(.bhRed)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            } else {
                Text("Download a JSON backup of all bills, people, and monthly data from your server.")
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)
                    .padding(.bottom, 8)

                if let exportURL = APIClient.shared.exportURL() {
                    Link(destination: exportURL) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("Export Backup")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BHSecondaryButtonStyle())
                } else {
                    Text("No server configured.")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)
                }
            }
        }
    }

    // MARK: - Danger Section

    @ViewBuilder
    private var dangerSection: some View {
        SettingsSection(title: "Danger Zone") {
            Text("Permanently remove all bills, people, and monthly data. This cannot be undone.")
                .font(.bhCaption)
                .foregroundColor(.bhMuted)
                .padding(.bottom, 8)

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

    // MARK: - Local backup file builder

    /// Encodes current state + monthly data and writes it to a uniquely
    /// named JSON file in the temp directory. ShareLink reads the URL.
    private func rebuildBackupFile() {
        do {
            let data = try vm.buildBackupJSON()
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("billhive-backup-\(stamp).json")
            try data.write(to: url, options: .atomic)
            backupFileURL = url
            backupBuildError = nil
        } catch {
            backupBuildError = "Couldn't build backup: \(error.localizedDescription)"
            backupFileURL = nil
        }
    }
}

// MARK: - Subscription Settings Sheet

/// Trial / purchase / restore controls in a focused sheet.
struct SubscriptionSettingsSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    PurchaseSettingsSection()
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle("Subscription")
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
}

// MARK: - About Settings Sheet

/// Version, credits, and a link out to the project site.
struct AboutSettingsSheet: View {
    let version: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 12) {
                            TriHexLogoMark(size: 64)
                            Text("BillHive")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.bhText)
                            Text("Version \(version)")
                                .font(.bhCaption)
                                .foregroundColor(.bhMuted)
                        }
                        .padding(.top, 32)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("BillHive helps a household track recurring bills, split them between people, and collect what's owed.")
                                .font(.bhCaption)
                                .foregroundColor(.bhMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 24)

                        VStack(spacing: 10) {
                            if let url = URL(string: "https://billhiveapp.com") {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "globe")
                                        Text("Visit billhiveapp.com")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(BHSecondaryButtonStyle())
                            }

                            if let url = URL(string: "https://github.com/MartyPortatoes/BillHive") {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                                        Text("GitHub Repository")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(BHSecondaryButtonStyle())
                            }
                        }
                        .padding(.horizontal, 24)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("About")
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
}
