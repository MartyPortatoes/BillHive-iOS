import SwiftUI

// URL helper functions (bhSafeWebURL, bhEncodeURLComponent) are defined in Utilities/URLHelpers.swift

// MARK: - Pay & Collect View

/// Central hub for paying bills and collecting from household members.
///
/// Two sections:
/// - **Collect** — shows each person who owes money with expandable details and
///   email/payment-app actions.
/// - **Pay** — lists every bill with an optional payment URL and a "Pay" button.
struct SendReceiveView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var expandedPersonId: String? = nil
    @State private var expandedSendId: String? = nil
    @State private var sendingEmailFor: String? = nil

    /// All household members except the primary user.
    var nonMePeople: [Person] { vm.state.people.filter { $0.id != "me" } }
    /// Per-person owed amounts for the current month, keyed by person ID.
    var owes: [String: PersonOwes] { vm.computePersonOwes() }

    var body: some View {
        NavigationStack {
            ZStack {
                HexBGView().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        MonthPickerBar()
                            .padding(.top, 12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pay & Collect")
                                .font(.bhViewTitle)
                                .foregroundColor(.bhText)
                            Text("Collect from others and pay your bills")
                                .font(.bhSubtitle)
                                .foregroundColor(.bhMuted)
                        }

                        // MARK: Collect Section

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.bhBlue.opacity(0.15))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBlue.opacity(0.25), lineWidth: 1))
                                        .frame(width: 32, height: 32)
                                    Text("↓")
                                        .font(.headline.weight(.bold))
                                        .foregroundColor(.bhBlue)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Collect")
                                        .font(.headline)
                                        .foregroundColor(.bhText)
                                    Text("Notify people what they owe and request payment")
                                        .font(.bhCaption)
                                        .foregroundColor(.bhMuted)
                                }
                            }

                            ForEach(nonMePeople.filter { (owes[$0.id]?.total ?? 0) > 0 }) { person in
                                ReceiveCard(
                                    person: person,
                                    personOwes: owes[person.id],
                                    isExpanded: expandedPersonId == person.id,
                                    isSendingEmail: sendingEmailFor == person.id,
                                    isPaymentReceived: vm.isPaymentReceived(person.id, for: vm.monthKey),
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedPersonId = expandedPersonId == person.id ? nil : person.id
                                        }
                                    },
                                    onSendEmail: {
                                        Task {
                                            sendingEmailFor = person.id
                                            await vm.sendPersonEmail(personId: person.id)
                                            sendingEmailFor = nil
                                        }
                                    },
                                    onTogglePayment: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            vm.togglePaymentReceived(person.id, for: vm.monthKey)
                                        }
                                    }
                                )
                            }
                        }

                        // MARK: Pay Section

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.bhAmber.opacity(0.15))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhAmber.opacity(0.25), lineWidth: 1))
                                        .frame(width: 32, height: 32)
                                    Text("↑")
                                        .font(.headline.weight(.bold))
                                        .foregroundColor(.bhAmber)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pay")
                                        .font(.headline)
                                        .foregroundColor(.bhText)
                                    Text("Pay your bills — tap Pay on any bill with a URL")
                                        .font(.bhCaption)
                                        .foregroundColor(.bhMuted)
                                }
                            }

                            ForEach(vm.state.bills.sorted { a, b in
                                // Bills with due dates first, sorted by day; no due date last
                                switch (a.dueDay, b.dueDay) {
                                case let (ad?, bd?): return ad < bd
                                case (_?, nil): return true
                                case (nil, _?): return false
                                case (nil, nil): return false
                                }
                            }) { bill in
                                SendCard(
                                    bill: bill,
                                    isExpanded: expandedSendId == bill.id,
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedSendId = expandedSendId == bill.id ? nil : bill.id
                                        }
                                    }
                                )
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                }
                .refreshable { await vm.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Receive Card

/// An expandable card for a single person in the Collect section.
///
/// Collapsed: person name, color dot, total owed, and payment app link.
/// Expanded: per-bill breakdown plus email and request-via-app action buttons.
struct ReceiveCard: View {
    let person: Person
    let personOwes: PersonOwes?
    let isExpanded: Bool
    let isSendingEmail: Bool
    let isPaymentReceived: Bool
    let onToggle: () -> Void
    let onSendEmail: () -> Void
    let onTogglePayment: () -> Void

    /// Constructs a Zelle payment URL from the person's pay ID or custom Zelle URL.
    /// Custom URLs are filtered through `bhSafeWebURL` so a malicious imported
    /// backup can't substitute a `tel:` or `myapp://` scheme.
    var zelleURL: URL? {
        if let zu = person.zelleUrl, let url = bhSafeWebURL(zu) { return url }
        if person.payMethod == .zelle, !person.payId.isEmpty {
            let encoded = bhEncodeURLComponent(person.payId)
            return URL(string: "https://enroll.zellepay.com/qr-codes?data=\(encoded)")
        }
        return nil
    }

    /// Constructs a Venmo deep link with the charge amount pre-filled.
    /// The handle is percent-encoded so `&` / `?` / `#` in a (corrupted) payId
    /// can't inject extra query parameters into the deep link.
    var venmoURL: URL? {
        guard person.payMethod == .venmo, !person.payId.isEmpty else { return nil }
        let raw = person.payId.hasPrefix("@") ? String(person.payId.dropFirst()) : person.payId
        let handle = bhEncodeURLComponent(raw)
        let amount = personOwes?.total ?? 0
        let note = bhEncodeURLComponent("Bills")
        return URL(string: "venmo://paycharge?txn=charge&recipients=\(handle)&amount=\(String(format: "%.2f", amount))&note=\(note)")
    }

    /// Constructs a Cash App profile URL from the person's cashtag.
    var cashAppURL: URL? {
        guard person.payMethod == .cashapp, !person.payId.isEmpty else { return nil }
        let raw = person.payId.hasPrefix("$") ? String(person.payId.dropFirst()) : person.payId
        let tag = bhEncodeURLComponent(raw)
        return URL(string: "https://cash.app/$\(tag)")
    }

    /// The resolved payment URL, trying Zelle → Venmo → Cash App.
    var payURL: URL? { zelleURL ?? venmoURL ?? cashAppURL }

    /// Human-readable label for the payment method button.
    var payLabel: String {
        switch person.payMethod {
        case .venmo: return "Venmo"
        case .cashapp: return "Cash App"
        default: return "Zelle"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header

            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: person.color) ?? .bhAmber)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(person.name)
                                .font(.bhBody)
                                .foregroundColor(.bhText)
                            if isPaymentReceived {
                                Text("Paid")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .cornerRadius(4)
                            } else {
                                Text("Awaiting")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.bhAmber)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.bhAmber.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                        Text(person.payMethod.displayName)
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                    }

                    Spacer()

                    Text((personOwes?.total ?? 0).asCurrency)
                        .font(.bhMoneyMedium)
                        .foregroundColor(isPaymentReceived ? .bhMuted : (Color(hex: person.color) ?? .bhAmber))
                        .strikethrough(isPaymentReceived, color: .bhMuted)

                    HStack(spacing: 6) {
                        // Payment button
                        if let url = payURL {
                            Link(destination: url) {
                                Text(payLabel)
                                    .font(.bhCaption.weight(.semibold))
                                    .foregroundColor(Color(hex: "#0c0d0f"))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: person.color) ?? .bhAmber)
                                    .cornerRadius(6)
                            }
                            .accessibilityLabel("Open \(payLabel) to collect \((personOwes?.total ?? 0).asCurrency) from \(person.name)")
                        }

                        Button(action: onToggle) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.bhMuted)
                                .frame(width: 24, height: 24)
                                .background(Color.bhSurface2)
                                .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.bhBorder, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(person.name), owes \((personOwes?.total ?? 0).asCurrency) via \(payLabel)")
            .accessibilityHint(isExpanded ? "Collapse" : "Expand for details")

            if isExpanded {
                // MARK: Expanded Content

                Divider().background(Color.bhBorder)
                VStack(alignment: .leading, spacing: 10) {
                    // Per-bill breakdown
                    ForEach(personOwes?.bills ?? [], id: \.billId) { bo in
                        HStack {
                            Text(bo.billName)
                                .font(.bhBodySecondary)
                                .foregroundColor(.bhMuted)
                            Spacer()
                            Text(bo.amount.asCurrency)
                                .font(.bhMoneySmall)
                                .foregroundColor(.bhText)
                        }
                        .padding(.vertical, 2)
                    }

                    Divider().background(Color.bhBorder)

                    // Actions — email & mark paid (equal width), request payment below
                    HStack(spacing: 8) {
                        Button(action: onSendEmail) {
                            HStack(spacing: 5) {
                                if isSendingEmail {
                                    ProgressView().tint(.bhText).scaleEffect(0.7)
                                } else {
                                    Image(systemName: "envelope")
                                        .font(.caption)
                                }
                                Text(isSendingEmail ? "Sending..." : "Send Email")
                            }
                            .font(.bhCaption.weight(.medium))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BHSecondaryButtonStyle())
                        .disabled(person.email.isEmpty || isSendingEmail)

                        Button(action: onTogglePayment) {
                            HStack(spacing: 5) {
                                Image(systemName: isPaymentReceived ? "arrow.uturn.backward" : "checkmark.circle")
                                    .font(.caption)
                                Text(isPaymentReceived ? "Mark Unpaid" : "Mark as Paid")
                            }
                            .font(.bhCaption.weight(.medium))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BHSecondaryButtonStyle())
                    }

                    if let url = payURL {
                        Link(destination: url) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                Text("Request via \(payLabel)")
                            }
                            .font(.bhCaption.weight(.medium))
                            .foregroundColor(Color(hex: "#0c0d0f"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.bhAmber)
                            .cornerRadius(7)
                        }
                    }
                }
                .padding(16)
                .background(Color.bhSurface2)
            }
        }
        .background(Color.bhSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bhBorder, lineWidth: 1))
    }
}

// MARK: - Send Card

/// A card for a single bill in the Pay section. Mirrors the Bills tab pattern:
/// the header is tappable to toggle expand/collapse, with a chevron at the
/// trailing edge. The Pay URL editor only shows when expanded — keeping the
/// list clean for everyday use while still allowing inline edits when needed.
struct SendCard: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill
    let isExpanded: Bool
    let onToggle: () -> Void

    /// Safely looks up the bill's current array index each time.
    private var billIndex: Int? { vm.state.bills.firstIndex(where: { $0.id == bill.id }) }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header row — tap anywhere except the Pay link to toggle.
            // The outer Button uses `.plain` style so the inner Link's tap
            // gesture wins inside its own bounds; everywhere else triggers
            // onToggle.
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(hex: bill.color)?.opacity(0.2) ?? Color.bhSurface3)
                            .frame(width: 34, height: 34)
                        Text(bill.icon).font(.body)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bill.name)
                            .font(.bhBody)
                            .foregroundColor(.bhText)
                        HStack(spacing: 6) {
                            Text(vm.getBillTotal(bill.id).asCurrency)
                                .font(.bhCaption)
                                .foregroundColor(.bhMuted)
                            if let label = bill.dueDayLabel {
                                let checkedOff = vm.state.checklist[vm.monthKey]?["pay_\(bill.id)"] ?? false
                                let autoPayDue: Bool = {
                                    guard bill.autoPay, let day = bill.dueDay else { return false }
                                    let cal = Calendar.current; let now = Date()
                                    return vm.selectedMonth == cal.component(.month, from: now)
                                        && vm.selectedYear == cal.component(.year, from: now)
                                        && cal.component(.day, from: now) >= day
                                }()
                                let paid = checkedOff || autoPayDue
                                let urgency = bill.dueUrgency(month: vm.selectedMonth, year: vm.selectedYear)
                                let color: Color = paid ? .bhGreen : urgency == .overdue ? .bhRed : urgency == .soon ? .bhAmber : .bhMuted
                                Text(paid ? "✓ Paid" : urgency == .overdue ? "Overdue" : "Due \(label)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(color.opacity(0.15))
                                    .cornerRadius(3)
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    if let url = bhSafeWebURL(bill.payUrl) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                Text("Pay")
                                    .font(.bhBodySecondary.weight(.semibold))
                            }
                            .foregroundColor(Color(hex: "#0c0d0f"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.bhAmber)
                            .cornerRadius(7)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.bhMuted)
                        .frame(width: 20)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(bill.name), \(vm.getBillTotal(bill.id).asCurrency)")
            .accessibilityHint(isExpanded ? "Collapse Pay URL editor" : "Expand to edit Pay URL")

            // MARK: Pay URL editor — only when expanded
            if isExpanded {
                Divider().background(Color.bhBorder)

                HStack(spacing: 8) {
                    Text("Pay URL")
                        .bhSectionTitle()
                        .frame(width: 60, alignment: .leading)

                    TextField("https://your-bank.com/pay", text: Binding(
                        get: { bill.payUrl },
                        set: { val in
                            guard let idx = billIndex else { return }
                            vm.state.bills[idx].payUrl = val
                            vm.save()
                        }
                    ))
                    .font(.bhCaption)
                    .foregroundColor(.bhText)
                    .textFieldStyle(.plain)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    if let url = bhSafeWebURL(bill.payUrl) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.subheadline)
                                .foregroundColor(.bhAmber)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.bhSurface2)
            }
        }
        .background(Color.bhSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isExpanded ? Color.bhBorder2 : Color.bhBorder, lineWidth: 1))
    }
}

// MARK: - Checklist Item Row

/// A single row in the monthly checklist with a custom checkbox and
/// strikethrough styling when completed.
struct ChecklistItemRow: View {
    let item: (id: String, label: String, done: Bool)
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(item.done ? Color.bhAmber : Color.clear)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(item.done ? Color.bhAmber : Color.bhBorder2, lineWidth: 1)
                        .frame(width: 18, height: 18)
                    if item.done {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(Color(hex: "#0c0d0f"))
                    }
                }

                Text(item.label)
                    .font(.bhBodySecondary)
                    .foregroundColor(item.done ? .bhMuted : .bhText)
                    .strikethrough(item.done, color: .bhMuted)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .opacity(item.done ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.label)
        .accessibilityValue(item.done ? "Checked" : "Unchecked")
        .accessibilityHint("Double-tap to toggle")
    }
}
