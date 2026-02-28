import Foundation
import SwiftUI
import Combine

// Used by the BillHive (local) target to trigger iOS Mail compose
struct MailComposeRequest: Identifiable {
    let id = UUID()
    let to: String
    let subject: String
    let body: String
}

@MainActor
class AppViewModel: ObservableObject {
    let isLocal: Bool

    @Published var state = AppState()
    @Published var monthly: [String: MonthData] = [:]
    @Published var emailConfig: EmailConfig? = nil
    @Published var isLoading = false
    @Published var error: String? = nil
    @Published var toastMessage: String? = nil
    @Published var pendingMailCompose: MailComposeRequest? = nil

    @Published var selectedYear: Int
    @Published var selectedMonth: Int

    private var saveDebounceTask: Task<Void, Never>? = nil
    private let api = APIClient.shared

    init(isLocal: Bool = false) {
        self.isLocal = isLocal
        let now = Date()
        let cal = Calendar.current
        selectedYear = cal.component(.year, from: now)
        selectedMonth = cal.component(.month, from: now)
    }

    var monthKey: String {
        MonthKey.from(year: selectedYear, month: selectedMonth)
    }

    var monthLabel: String {
        MonthKey.label(monthKey)
    }

    var currentMonthData: MonthData {
        monthly[monthKey] ?? MonthData()
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        error = nil
        if isLocal {
            state = LocalStorageManager.shared.loadState()
            monthly = LocalStorageManager.shared.loadMonths()
            autoFillPreservedBills()
        } else {
            do {
                async let stateTask = api.getState()
                async let monthsTask = api.getAllMonths()
                async let emailTask = api.getEmailConfig()
                state = try await stateTask
                monthly = try await monthsTask
                emailConfig = try? await emailTask
                autoFillPreservedBills()
            } catch {
                self.error = error.localizedDescription
            }
        }
        isLoading = false
    }

    func refresh() async {
        await load()
    }

    // MARK: - Save (debounced for config, immediate for monthly)

    func save() {
        if isLocal {
            LocalStorageManager.shared.saveState(state)
            return
        }
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
            guard !Task.isCancelled else { return }
            do {
                try await api.saveState(state)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func saveMonthNow(_ key: String? = nil) {
        let key = key ?? monthKey
        guard let data = monthly[key] else { return }
        if isLocal {
            LocalStorageManager.shared.saveMonth(key, data: data)
            return
        }
        Task {
            do {
                try await api.saveMonth(key, data: data)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

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

    // MARK: - Business Logic

    func getBillTotal(_ billId: String) -> Double {
        currentMonthData.totals[billId] ?? 0
    }

    func setBillTotal(_ billId: String, value: Double) {
        if monthly[monthKey] == nil { monthly[monthKey] = MonthData() }
        monthly[monthKey]!.totals[billId] = value
        saveMonthSnapshot()
    }

    func getLineAmount(_ billId: String, lineId: String) -> Double {
        currentMonthData.amounts[billId]?[lineId] ?? 0
    }

    func setLineAmount(_ billId: String, lineId: String, value: Double) {
        if monthly[monthKey] == nil { monthly[monthKey] = MonthData() }
        if monthly[monthKey]!.amounts[billId] == nil {
            monthly[monthKey]!.amounts[billId] = [:]
        }
        monthly[monthKey]!.amounts[billId]![lineId] = value
        saveMonthSnapshot()
    }

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
                    let allOthers = bill.lines
                        .filter { $0.id != bill.remainderLineId }
                        .reduce(0.0) { $0 + (md.amounts[bill.id]?[$1.id] ?? 0) }
                    let billTotal = md.totals[bill.id] ?? allOthers  // fallback
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

        // Consolidate duplicate bill entries per person
        for (pid, _) in result {
            var consolidated: [String: BillOwed] = [:]
            for bo in result[pid]!.bills {
                if consolidated[bo.billId] != nil {
                    consolidated[bo.billId]!.amount += bo.amount  // This won't compile, BillOwed is struct
                } else {
                    consolidated[bo.billId] = bo
                }
            }
            result[pid]?.bills = Array(consolidated.values).sorted { $0.billName < $1.billName }
        }

        return result
    }

    func computeMyTotal() -> Double {
        var total = 0.0
        for bill in state.bills {
            let split = computeBillSplit(bill)
            total += split["me"] ?? 0
        }
        return total
    }

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

    func onMonthChange() {
        autoFillPreservedBills()
        saveMonthSnapshot()
    }

    // MARK: - People

    func addPerson() {
        let colors = Person.personColors
        let color = colors[state.people.count % colors.count]
        state.people.append(Person(color: color))
        save()
    }

    func removePerson(at index: Int) {
        state.people.remove(at: index)
        save()
    }

    func getPerson(_ id: String) -> Person? {
        state.people.first { $0.id == id }
    }

    // MARK: - Bills

    func addBill() {
        let lineId = "l\(Int(Date().timeIntervalSince1970 * 1000))"
        var bill = Bill()
        bill.lines = [BillLine(id: lineId, desc: "My share", personId: "me", value: 100)]
        bill.remainderLineId = lineId
        state.bills.append(bill)
        save()
    }

    func removeBill(_ bill: Bill) {
        state.bills.removeAll { $0.id == bill.id }
        save()
    }

    func addLine(to billId: String) {
        guard let idx = state.bills.firstIndex(where: { $0.id == billId }) else { return }
        let defaultPersonId = state.people.first(where: { $0.id != "me" })?.id ?? "me"
        state.bills[idx].lines.append(BillLine(
            desc: "Line",
            personId: defaultPersonId,
            value: 0
        ))
        save()
    }

    func removeLine(billId: String, lineId: String) {
        guard let idx = state.bills.firstIndex(where: { $0.id == billId }) else { return }
        state.bills[idx].lines.removeAll { $0.id == lineId }
        save()
    }

    // MARK: - Checklist

    func checklistItems(for key: String) -> [(id: String, label: String, done: Bool)] {
        var items: [(id: String, label: String, done: Bool)] = []
        let checks = monthly[key] != nil
        _ = checks
        let cl = state.checklist[key] ?? [:]

        // Email sent items
        for person in state.people where person.id != "me" {
            let id = "email-\(person.id)"
            items.append((id: id, label: "Email sent to \(person.name)", done: cl[id] ?? false))
        }
        // Bill paid items
        for bill in state.bills {
            let id = "paid-\(bill.id)"
            items.append((id: id, label: "\(bill.name) paid", done: cl[id] ?? false))
        }
        // Payment received items
        for person in state.people where person.id != "me" {
            let id = "recv-\(person.id)"
            items.append((id: id, label: "Payment received from \(person.name)", done: cl[id] ?? false))
        }
        return items
    }

    func toggleChecklistItem(_ itemId: String, for key: String) {
        if state.checklist[key] == nil { state.checklist[key] = [:] }
        let current = state.checklist[key]?[itemId] ?? false
        state.checklist[key]?[itemId] = !current
        save()
    }

    // MARK: - Toast

    func toast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if toastMessage == message { toastMessage = nil }
        }
    }

    // MARK: - Email Send

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

    private func buildLocalEmailText(person: Person, personOwes: PersonOwes?) -> String {
        let greeting = person.greeting.isEmpty ? "Hi \(person.name)," : person.greeting
        var lines = [greeting, "", "Here's your bill summary for \(monthLabel):", ""]
        for bo in personOwes?.bills ?? [] {
            lines.append("• \(bo.billName): \(String(format: "$%.2f", bo.amount))")
        }
        lines.append("")
        lines.append(String(format: "Total: $%.2f", personOwes?.total ?? 0))
        return lines.joined(separator: "\n")
    }
}
