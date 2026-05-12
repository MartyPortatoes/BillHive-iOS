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

/// People management — names, colors, payment methods, and emails.
/// Greetings have been moved to the Email & Greetings sheet.
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

// MARK: - Privacy & Data Sheet

/// Merged sheet combining App Lock (formerly Privacy & Security) with
/// backup/export and the danger zone (formerly Data & Backup).
struct PrivacyDataSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lock = AppLockManager.shared

    @State private var enableError: String?
    @State private var isAuthenticating = false
    @State private var showClearConfirm = false
    @State private var backupFileURL: URL? = nil
    @State private var backupBuildError: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // App Lock
                        SettingsSection(title: "App Lock") {
                            Toggle(isOn: Binding(
                                get: { lock.isEnabled },
                                set: { newValue in handleLockToggle(newValue) }
                            )) {
                                HStack(spacing: 8) {
                                    Image(systemName: AppLockManager.biometrySymbolName)
                                        .foregroundColor(.bhAmber)
                                    Text("Require \(AppLockManager.biometryDisplayName)")
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

                        Text("When enabled, the app requires \(AppLockManager.biometryDisplayName) to open on cold start and after returning from the background.")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)

                        // Backup
                        backupSection

                        // Danger Zone
                        dangerSection

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Data & Privacy")
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

    // MARK: - App Lock Toggle

    private func handleLockToggle(_ newValue: Bool) {
        enableError = nil
        if newValue {
            isAuthenticating = true
            Task {
                let ok = await lock.tryEnable()
                if !ok {
                    enableError = "Couldn't authenticate. Make sure \(AppLockManager.biometryDisplayName) is enabled in iOS Settings, and that you have a device passcode set."
                }
                isAuthenticating = false
            }
        } else {
            lock.disable()
        }
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

// MARK: - About & Upgrade Sheet

/// Merged sheet combining the About info (logo, version, links) with
/// subscription/purchase controls.
struct AboutUpgradeSheet: View {
    let version: String
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Logo + version
                        VStack(spacing: 12) {
                            TriHexLogoMark(size: 64)
                            Text(PurchaseManager.brandName)
                                .font(.title2.weight(.bold))
                                .foregroundColor(.bhText)
                            Text("Version \(version)")
                                .font(.bhCaption)
                                .foregroundColor(.bhMuted)
                        }
                        .padding(.top, 32)

                        Text("\(PurchaseManager.brandName) helps a household track recurring bills, split them between people, and collect what's owed.")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        // Subscription
                        PurchaseSettingsSection()
                            .padding(.horizontal, 16)

                        // Links
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
