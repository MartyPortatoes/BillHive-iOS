import Foundation
import SwiftUI
import Combine

// MARK: - Mail Compose Request

/// Payload for triggering the iOS Mail compose sheet (BillHive standalone target only).
struct MailComposeRequest: Identifiable {
    let id = UUID()
    let to: String
    let subject: String
    let body: String
}

// MARK: - App View Model

/// Central view model that owns all application state and business logic.
///
/// Operates in two modes depending on the `isLocal` flag:
/// - **Local (BillHive)**: Reads/writes state via `CloudStorageManager` (iCloud)
///   or `LocalStorageManager` (fallback). No server needed.
/// - **Remote (SelfHive)**: Communicates with a self-hosted Node.js server
///   via `APIClient` for all CRUD operations.
///
/// All published properties drive SwiftUI views. Mutations happen on `@MainActor`
/// to guarantee thread-safe UI updates.
@MainActor
class AppViewModel: ObservableObject {

    // MARK: - Configuration

    /// Whether this instance uses local (iCloud/file) storage vs a remote server.
    let isLocal: Bool

    // MARK: - Published State

    /// The complete app configuration — people, bills, settings, checklists.
    @Published var state = AppState()
    /// Per-month financial data keyed by month key (e.g. "2026-03").
    @Published var monthly: [String: MonthData] = [:]
    /// Server-side email relay configuration (remote mode only).
    @Published var emailConfig: EmailConfig? = nil
    /// Whether a load/refresh operation is in progress.
    @Published var isLoading = false
    /// User-facing error message from the most recent failed operation.
    @Published var error: String? = nil
    /// Transient toast message displayed at the bottom of the screen.
    @Published var toastMessage: String? = nil
    /// Pending mail compose request (BillHive standalone target only).
    @Published var pendingMailCompose: MailComposeRequest? = nil
    /// Whether the paywall sheet is being presented.
    @Published var showPaywall: Bool = false
    /// Context string for the paywall (e.g. "Unlock Trends to see analytics").
    @Published var paywallContext: String? = nil
    /// Currently selected year in the month picker.
    @Published var selectedYear: Int
    /// Currently selected month (1–12) in the month picker.
    @Published var selectedMonth: Int

    // MARK: - Private

    /// Debounce task for state saves to the remote server.
    /// Prevents rapid-fire network requests while the user is editing.
    private var saveDebounceTask: Task<Void, Never>? = nil
    private let api = APIClient.shared
    /// Observer token for iCloud file-change notifications (local mode only).
    private var cloudChangeObserver: Any?

    // MARK: - Init / Deinit

    init(isLocal: Bool = false) {
        self.isLocal = isLocal
        let now = Date()
        let cal = Calendar.current
        selectedYear = cal.component(.year, from: now)
        selectedMonth = cal.component(.month, from: now)

        #if BILLHIVE_LOCAL
        if isLocal {
            cloudChangeObserver = NotificationCenter.default.addObserver(
                forName: CloudStorageManager.filesDidChangeExternally,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.reloadFromCloud()
                }
            }
        }
        #endif
    }

    deinit {
        if let observer = cloudChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Computed Properties

    /// The month key for the currently selected year/month (e.g. "2026-03").
    var monthKey: String {
        MonthKey.from(year: selectedYear, month: selectedMonth)
    }

    /// Human-readable label for the selected month (e.g. "March 2026").
    var monthLabel: String {
        MonthKey.label(monthKey)
    }

    /// The `MonthData` for the currently selected month, or an empty default.
    var currentMonthData: MonthData {
        monthly[monthKey] ?? MonthData()
    }

    // MARK: - Load

    /// Loads all data from the appropriate storage backend.
    ///
    /// In local mode, reads from iCloud/local files synchronously.
    /// In remote mode, fetches state, months, and email config concurrently
    /// from the server using `async let`.
    func load() async {
        isLoading = true
        error = nil
        if isLocal {
            #if BILLHIVE_LOCAL
            state = CloudStorageManager.shared.loadState()
            monthly = CloudStorageManager.shared.loadMonths()
            #else
            state = LocalStorageManager.shared.loadState()
            monthly = LocalStorageManager.shared.loadMonths()
            #endif
            normalizeStatePeople()
            normalizePctLines()
            autoFillPreservedBills()
        } else {
            do {
                async let stateTask = api.getState()
                async let monthsTask = api.getAllMonths()
                async let emailTask = api.getEmailConfig()
                state = try await stateTask
                monthly = try await monthsTask
                emailConfig = try? await emailTask
                normalizeStatePeople()
                normalizePctLines()
                autoFillPreservedBills()
            } catch {
                self.error = error.localizedDescription
            }
        }
        CurrencyManager.currencyCode = state.settings.currencyCode
        isLoading = false
    }

    /// Ensures the primary "me" person always exists with the literal ID "me".
    ///
    /// Handles three cases:
    /// 1. No people at all — inserts a default "Me" entry at index 0.
    /// 2. A person with id "me" already exists — no-op.
    /// 3. People exist but none has id "me" (legacy timestamp IDs) — promotes
    ///    the first person to "me" and remaps all bill line references.
    private func normalizeStatePeople() {
        if state.people.isEmpty {
            state.people = [Person(id: "me", name: "Me", color: "#F5A800")]
            save()
            return
        }
        guard !state.people.contains(where: { $0.id == "me" }) else { return }

        // Legacy migration: first person was created with a timestamp ID
        let oldId = state.people[0].id
        state.people[0].id = "me"
        for bi in state.bills.indices {
            for li in state.bills[bi].lines.indices {
                if state.bills[bi].lines[li].personId == oldId {
                    state.bills[bi].lines[li].personId = "me"
                }
                if state.bills[bi].lines[li].coveredById == oldId {
                    state.bills[bi].lines[li].coveredById = "me"
                }
            }
        }
        save()
    }

    /// Ensures every pct-split bill has line values that sum to 100.
    ///
    /// Bills loaded from JSON may have all-zero percentage values if they were
    /// saved before percentages were configured, which causes `computeBillSplit`
    /// to return $0.00 for every person despite a non-zero bill total.
    private func normalizePctLines() {
        var changed = false
        for i in state.bills.indices {
            guard state.bills[i].splitType == .pct else { continue }
            let sum = state.bills[i].lines.reduce(0.0) { $0 + $1.value }
            if sum == 0 {
                redistributePctLines(billIdx: i)
                changed = true
            }
        }
        if changed { save() }
    }

    /// Convenience wrapper that reloads all data.
    func refresh() async {
        await load()
    }

    #if BILLHIVE_LOCAL
    /// Reloads data from iCloud if it changed on another device.
    ///
    /// Compares with current in-memory state to avoid unnecessary re-renders.
    func reloadFromCloud() async {
        guard isLocal else { return }
        let newState = CloudStorageManager.shared.loadState()
        let newMonthly = CloudStorageManager.shared.loadMonths()

        if newState != state {
            state = newState
            normalizeStatePeople()
            normalizePctLines()
        }
        if newMonthly != monthly {
            monthly = newMonthly
            autoFillPreservedBills()
        }
    }
    #endif

    // MARK: - Save

    /// Persists the current `AppState` (debounced for remote, immediate for local).
    ///
    /// In remote mode, a 600ms debounce prevents rapid-fire API calls while
    /// the user is actively editing fields.
    /// Builds a single JSON document containing the complete app state and
    /// all monthly data. Used by the local-target backup export to give the
    /// user a portable snapshot they can share or save to Files.
    ///
    /// Format mirrors the web app's `/api/export` response:
    /// `{ "state": ..., "monthly": ..., "exportedAt": "ISO-8601" }`
    func buildBackupJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stateAny = try JSONSerialization.jsonObject(with: encoder.encode(state))
        let monthlyAny = try JSONSerialization.jsonObject(with: encoder.encode(monthly))
        let payload: [String: Any] = [
            "state": stateAny,
            "monthly": monthlyAny,
            "exportedAt": ISO8601DateFormatter().string(from: Date())
        ]
        return try JSONSerialization.data(withJSONObject: payload,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    /// Resets state and monthly data to empty defaults and persists.
    /// Works for both local (iCloud / Documents) and remote (server) modes.
    func clearAllData() async {
        state = AppState()
        monthly = [:]
        if isLocal {
            #if BILLHIVE_LOCAL
            CloudStorageManager.shared.saveState(state)
            CloudStorageManager.shared.saveAllMonths(monthly)
            #else
            LocalStorageManager.shared.saveState(state)
            LocalStorageManager.shared.saveAllMonths(monthly)
            #endif
        } else {
            try? await api.saveState(state)
            // For remote, individual months are kept as the server already
            // has them — `getAllMonths()` will reflect this empty state.
        }
        await load()
    }

    func save() {
        if isLocal {
            #if BILLHIVE_LOCAL
            CloudStorageManager.shared.saveState(state)
            #else
            LocalStorageManager.shared.saveState(state)
            #endif
            return
        }
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do {
                try await api.saveState(state)
            } catch {
                self.toast("Save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Immediately persists the specified month's data.
    ///
    /// - Parameter key: The month key to save. Defaults to the currently selected month.
    func saveMonthNow(_ key: String? = nil) {
        let key = key ?? monthKey
        guard let data = monthly[key] else { return }
        if isLocal {
            #if BILLHIVE_LOCAL
            CloudStorageManager.shared.saveMonth(key, data: data)
            #else
            LocalStorageManager.shared.saveMonth(key, data: data)
            #endif
            return
        }
        Task {
            do {
                try await api.saveMonth(key, data: data)
            } catch {
                self.toast("Save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Recomputes cached summary fields (`_myTotal`, `_owes`) and saves the month.
    ///
    /// Called after any amount change so that the Trends view has accurate
    /// historical snapshots without needing to recompute from raw line data.
    func saveMonthSnapshot() {
        let key = monthKey
        var data = monthly[key] ?? MonthData()
        data._myTotal = computeMyTotal()
        var owes: [String: Double] = [:]
        for (pid, info) in computePersonOwes() {
            owes[pid] = info.total
        }
        data._owes = owes
        monthly[key] = data
        saveMonthNow(key)
    }

    // MARK: - Business Logic (Bill Totals & Amounts)

    /// Returns the total for a bill in the current month.
    func getBillTotal(_ billId: String) -> Double {
        currentMonthData.totals[billId] ?? 0
    }

    /// Sets the total for a bill in the current month and saves.
    func setBillTotal(_ billId: String, value: Double) {
        if monthly[monthKey] == nil { monthly[monthKey] = MonthData() }
        monthly[monthKey]!.totals[billId] = value
        saveMonthSnapshot()
    }

    /// Returns the fixed amount for a specific line in the current month.
    func getLineAmount(_ billId: String, lineId: String) -> Double {
        currentMonthData.amounts[billId]?[lineId] ?? 0
    }

    /// Sets the fixed amount for a specific line in the current month and saves.
    func setLineAmount(_ billId: String, lineId: String, value: Double) {
        if monthly[monthKey] == nil { monthly[monthKey] = MonthData() }
        if monthly[monthKey]!.amounts[billId] == nil {
            monthly[monthKey]!.amounts[billId] = [:]
        }
        monthly[monthKey]!.amounts[billId]![lineId] = value
        saveMonthSnapshot()
    }

    // MARK: - Business Logic (Split Calculations)

    /// Computes how the bill total is split among payers for the current month.
    ///
    /// Returns a dictionary of `[personId: dollarAmount]`. The "payer" is
    /// `coveredById` if set, otherwise the line's own `personId`.
    ///
    /// - Parameter bill: The bill to compute the split for.
    /// - Returns: A mapping of person IDs to their dollar share of this bill.
    func computeBillSplit(_ bill: Bill) -> [String: Double] {
        var result: [String: Double] = [:]
        let md = currentMonthData

        for line in bill.lines {
            let amount: Double
            if bill.splitType == .pct {
                let total = md.totals[bill.id] ?? 0
                amount = total * line.value / 100.0
            } else {
                if line.id == bill.remainderLineId {
                    // Remainder line gets total minus the sum of all other fixed lines
                    let allOthers = bill.lines
                        .filter { $0.id != bill.remainderLineId }
                        .reduce(0.0) { $0 + (md.amounts[bill.id]?[$1.id] ?? 0) }
                    let billTotal = md.totals[bill.id] ?? allOthers
                    amount = max(0, billTotal - allOthers)
                } else {
                    amount = md.amounts[bill.id]?[line.id] ?? 0
                }
            }

            let payerId = line.coveredById ?? line.personId
            result[payerId, default: 0] += amount
        }
        return result
    }

    /// Computes what each non-"me" person owes across all bills for the current month.
    ///
    /// Returns a dictionary of `[personId: PersonOwes]` with a per-bill breakdown.
    /// Duplicate bill entries for the same person (e.g. when they cover someone else's
    /// share on the same bill) are consolidated into a single entry.
    func computePersonOwes() -> [String: PersonOwes] {
        var result: [String: PersonOwes] = [:]

        for bill in state.bills {
            for line in bill.lines {
                let payerId = line.coveredById ?? line.personId
                if payerId == "me" { continue }

                let amount: Double
                if bill.splitType == .pct {
                    let total = currentMonthData.totals[bill.id] ?? 0
                    amount = total * line.value / 100.0
                } else if line.id == bill.remainderLineId {
                    let allOthers = bill.lines
                        .filter { $0.id != bill.remainderLineId }
                        .reduce(0.0) { $0 + (currentMonthData.amounts[bill.id]?[$1.id] ?? 0) }
                    let billTotal = currentMonthData.totals[bill.id] ?? allOthers
                    amount = max(0, billTotal - allOthers)
                } else {
                    amount = currentMonthData.amounts[bill.id]?[line.id] ?? 0
                }

                if result[payerId] == nil {
                    result[payerId] = PersonOwes(personId: payerId, total: 0, bills: [])
                }

                var billName = bill.name
                if line.coveredById != nil && line.coveredById != line.personId {
                    if let covered = state.people.first(where: { $0.id == line.personId }) {
                        billName += " (covers \(covered.name))"
                    }
                }

                let billOwed = BillOwed(
                    billId: bill.id,
                    billName: billName,
                    amount: amount,
                    coveredNote: line.coveredById != nil ? "covers \(line.personId)" : nil
                )
                result[payerId]?.total += amount
                result[payerId]?.bills.append(billOwed)
            }
        }

        // Consolidate duplicate bill entries per person (e.g. when one person
        // covers multiple lines on the same bill, merge them into one entry).
        for (pid, _) in result {
            var consolidated: [String: BillOwed] = [:]
            for bo in result[pid]!.bills {
                if var existing = consolidated[bo.billId] {
                    existing.amount += bo.amount
                    consolidated[bo.billId] = existing
                } else {
                    consolidated[bo.billId] = bo
                }
            }
            result[pid]?.bills = Array(consolidated.values).sorted { $0.billName < $1.billName }
        }

        return result
    }

    /// Computes the primary user's ("me") total share across all bills.
    func computeMyTotal() -> Double {
        var total = 0.0
        for bill in state.bills {
            let split = computeBillSplit(bill)
            total += split["me"] ?? 0
        }
        return total
    }

    /// Copies the previous month's amounts into the current month for bills
    /// that have `preserve` enabled, but only if the current month has no
    /// data for that bill yet.
    func autoFillPreservedBills() {
        let key = monthKey
        let prevKey = MonthKey.previous(of: key)
        guard let prevData = monthly[prevKey] else { return }

        var changed = false
        for bill in state.bills {
            guard bill.preserve else { continue }
            let curData = monthly[key]
            let hasTotal = (curData?.totals[bill.id] ?? 0) > 0
            let hasLines = bill.lines.contains { (curData?.amounts[bill.id]?[$0.id] ?? 0) > 0 }
            if hasTotal || hasLines { continue }

            if monthly[key] == nil { monthly[key] = MonthData() }
            if let t = prevData.totals[bill.id] {
                monthly[key]?.totals[bill.id] = t
                changed = true
            }
            if let lineAmts = prevData.amounts[bill.id] {
                monthly[key]?.amounts[bill.id] = lineAmts
                changed = true
            }
        }

        if changed { saveMonthNow(key) }
    }

    // MARK: - Month Navigation

    /// Called when the user changes the selected month or year.
    ///
    /// In local mode, auto-fills preserved bills and saves a snapshot.
    /// In remote mode, fetches the latest server data first so autoFill
    /// doesn't overwrite values entered in the web app for non-preserved bills.
    func onMonthChange() {
        if isLocal {
            autoFillPreservedBills()
            saveMonthSnapshot()
            return
        }
        Task {
            if let fresh = try? await api.getMonth(monthKey) {
                monthly[monthKey] = fresh
            }
            autoFillPreservedBills()
            saveMonthSnapshot()
        }
    }

    // MARK: - People Management

    /// Adds a new person with the next color from the rotating palette.
    func addPerson() {
        let colors = Person.personColors
        let color = colors[state.people.count % colors.count]
        state.people.append(Person(color: color))
        save()
    }

    /// Removes the person at the given index.
    func removePerson(at index: Int) {
        state.people.remove(at: index)
        save()
    }

    /// Looks up a person by their ID.
    func getPerson(_ id: String) -> Person? {
        state.people.first { $0.id == id }
    }

    // MARK: - Bill Management

    /// Adds a new bill with a single "My share" line at 100%.
    func addBill() {
        let lineId = "l\(Int(Date().timeIntervalSince1970 * 1000))"
        var bill = Bill()
        bill.lines = [BillLine(id: lineId, desc: "My share", personId: "me", value: 100)]
        bill.remainderLineId = lineId
        state.bills.append(bill)
        save()
    }

    /// Removes a bill by ID.
    func removeBill(_ bill: Bill) {
        state.bills.removeAll { $0.id == bill.id }
        save()
    }

    /// Adds a new line to the specified bill.
    ///
    /// Defaults to the first non-"me" person, or "me" if no others exist.
    /// If the bill uses percentage splitting, redistributes all lines equally.
    func addLine(to billId: String) {
        guard let idx = state.bills.firstIndex(where: { $0.id == billId }) else { return }
        let defaultPersonId = state.people.first(where: { $0.id != "me" })?.id ?? "me"
        state.bills[idx].lines.append(BillLine(
            desc: "Line",
            personId: defaultPersonId,
            value: 0
        ))
        if state.bills[idx].splitType == .pct {
            redistributePctLines(billIdx: idx)
        }
        save()
    }

    /// Removes a specific line from a bill.
    ///
    /// If the bill uses percentage splitting, redistributes remaining lines equally.
    func removeLine(billId: String, lineId: String) {
        guard let idx = state.bills.firstIndex(where: { $0.id == billId }) else { return }
        state.bills[idx].lines.removeAll { $0.id == lineId }
        if state.bills[idx].splitType == .pct {
            redistributePctLines(billIdx: idx)
        }
        save()
    }

    /// Sets one line's percentage and redistributes the remainder equally among other lines.
    ///
    /// The edited line is "locked" at the new value. All other lines share the
    /// remaining percentage equally, with rounding correction on the last line
    /// to ensure the total stays at exactly 100%.
    ///
    /// - Parameters:
    ///   - billId: The bill containing the line.
    ///   - lineId: The line being edited.
    ///   - value: The new percentage (clamped to 0–100).
    func setLinePct(billId: String, lineId: String, value: Double) {
        guard let bi = state.bills.firstIndex(where: { $0.id == billId }) else { return }
        guard let li = state.bills[bi].lines.firstIndex(where: { $0.id == lineId }) else { return }
        let clamped = max(0, min(100, value))
        state.bills[bi].lines[li].value = clamped
        let otherIndices = state.bills[bi].lines.indices.filter { $0 != li }
        let n = otherIndices.count
        if n > 0 {
            let remaining = 100.0 - clamped
            let share = ((remaining / Double(n)) * 100).rounded() / 100
            let last  = remaining - share * Double(n - 1)
            for (offset, idx) in otherIndices.enumerated() {
                state.bills[bi].lines[idx].value = (offset == n - 1) ? last : share
            }
        }
        save()
    }

    /// Distributes percentages equally across all lines in a bill.
    ///
    /// Rounds each share to 2 decimal places and assigns the true remainder
    /// to the last line so that all values sum to exactly 100.
    private func redistributePctLines(billIdx: Int) {
        let n = state.bills[billIdx].lines.count
        guard n > 0 else { return }
        let share = ((100.0 / Double(n)) * 100).rounded() / 100
        let last  = 100.0 - share * Double(n - 1)
        for i in 0 ..< n {
            state.bills[billIdx].lines[i].value = (i == n - 1) ? last : share
        }
    }

    // MARK: - Checklist

    /// Builds the checklist items for a given month.
    ///
    /// Mirrors the web app's `buildChecklistDefs()` exactly — same item IDs
    /// and labels so checked states sync correctly via `/api/state`.
    ///
    /// Order:
    /// 1. "Enter all bill amounts" (static)
    /// 2. Per person who owes > 0: payment-method-specific request task
    /// 3. Per person who owes > 0: "Email bill summary to [name]"
    /// 4. Per bill (non-autopay, has payUrl): "Pay [bill]"
    func checklistItems(for key: String) -> [(id: String, label: String, done: Bool)] {
        var items: [(id: String, label: String, done: Bool)] = []
        let cl = state.checklist[key] ?? [:]
        let owes = computePersonOwes()

        // Static first item
        let enterId = "enter"
        items.append((id: enterId, label: "Enter all bill amounts", done: cl[enterId] ?? false))

        // Per-person collect items (only people who actually owe money)
        let owingPeople = state.people.filter { $0.id != "me" && (owes[$0.id]?.total ?? 0) > 0 }

        for person in owingPeople {
            // Payment-method-specific request task
            switch person.payMethod {
            case .zelle:
                let id = "zelle_\(person.id)"
                items.append((id: id, label: "Send Zelle request to \(person.name)", done: cl[id] ?? false))
            case .venmo:
                let id = "venmo_\(person.id)"
                items.append((id: id, label: "Send Venmo request to \(person.name)", done: cl[id] ?? false))
            case .cashapp:
                let id = "cashapp_\(person.id)"
                items.append((id: id, label: "Send Cash App request to \(person.name)", done: cl[id] ?? false))
            case .none, .manual:
                break
            }
            // Email task
            let emailId = "email_\(person.id)"
            items.append((id: emailId, label: "Email bill summary to \(person.name)", done: cl[emailId] ?? false))
        }

        // Per-bill pay items (skip auto-pay, only include bills with a payUrl)
        for bill in state.bills where !bill.autoPay && !bill.payUrl.isEmpty {
            let id = "pay_\(bill.id)"
            items.append((id: id, label: "Pay \(bill.name)", done: cl[id] ?? false))
        }

        return items
    }

    /// Toggles a checklist item's done state for the given month.
    func toggleChecklistItem(_ itemId: String, for key: String) {
        if state.checklist[key] == nil { state.checklist[key] = [:] }
        let current = state.checklist[key]?[itemId] ?? false
        state.checklist[key]?[itemId] = !current
        save()
    }

    // MARK: - Purchase Gating

    /// Whether the app is fully unlocked (purchased or within trial).
    var isUnlocked: Bool {
        PurchaseManager.shared.isUnlocked
    }

    /// Presents the paywall sheet with an optional context message.
    func presentPaywall(context: String? = nil) {
        paywallContext = context
        showPaywall = true
    }

    // MARK: - Toast

    /// Shows a transient toast message that auto-dismisses after ~2.8 seconds.
    func toast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .milliseconds(2800))
            if toastMessage == message { toastMessage = nil }
        }
    }

    // MARK: - Email Send

    /// Sends a bill summary email to the specified person.
    ///
    /// In local mode, presents the iOS Mail compose sheet. In remote mode,
    /// dispatches the email through the server's `/api/email/send` endpoint.
    func sendPersonEmail(personId: String) async {
        guard let person = getPerson(personId) else { return }
        guard !person.email.isEmpty else {
            toast("No email address for \(person.name)")
            return
        }
        let owes = computePersonOwes()
        let personOwes = owes[personId]

        if isLocal {
            let body = buildLocalEmailText(person: person, personOwes: personOwes)
            pendingMailCompose = MailComposeRequest(
                to: person.email,
                subject: "Bills for \(monthLabel)",
                body: body
            )
            return
        }

        let billsPayload = (personOwes?.bills ?? []).map { ["name": $0.billName, "amount": $0.amount] as [String: Any] }
        do {
            try await api.sendEmail(
                to: person.email,
                greeting: person.greeting.isEmpty ? "Hi \(person.name)," : person.greeting,
                personName: person.name,
                accentColor: person.color,
                monthLabel: monthLabel,
                bills: billsPayload,
                total: personOwes?.total ?? 0,
                payMethod: person.payMethod.rawValue,
                payId: person.payId,
                zelleUrl: person.zelleUrl
            )
            toast("Email sent to \(person.name)")
        } catch {
            toast("Failed: \(error.localizedDescription)")
        }
    }

    /// Builds a plain-text email body for the iOS Mail compose sheet.
    private func buildLocalEmailText(person: Person, personOwes: PersonOwes?) -> String {
        let greeting = person.greeting.isEmpty ? "Hi \(person.name)," : person.greeting
        var lines = [greeting, "", "Here's your bill summary for \(monthLabel):", ""]
        for bo in personOwes?.bills ?? [] {
            lines.append("• \(bo.billName): \(bo.amount.asCurrency)")
        }
        lines.append("")
        lines.append("Total: \((personOwes?.total ?? 0).asCurrency)")
        return lines.joined(separator: "\n")
    }
}
