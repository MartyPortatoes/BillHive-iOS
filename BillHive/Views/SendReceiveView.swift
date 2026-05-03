import SwiftUI

// MARK: - URL Sanitization

/// Returns `url` only if it parses cleanly and uses the `https` scheme.
/// User-entered or imported URLs may otherwise contain `tel:`, `sms:`, `file:`,
/// or arbitrary app-scheme URLs that would route to whatever handler the user
/// has installed — turning a "Pay" button into a deep-link injection vector.
func bhSafeWebURL(_ raw: String) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          scheme == "https" else { return nil }
    return url
}

/// Percent-encodes a single URL path or query component. Used to keep
/// user-entered Venmo handles and CashApp tags from injecting `&` / `?` / `#`
/// into deep-link URLs we construct.
func bhEncodeURLComponent(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
}

// MARK: - Pay & Collect View

/// Central hub for paying bills and collecting from household members.
///
/// Three sections:
/// - **Collect** — shows each person who owes money with expandable details and
///   email/payment-app actions.
/// - **Pay** — lists every bill with an optional payment URL and a "Pay" button.
/// - **Checklist** — per-month task checklist for tracking what's been done.
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
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedPersonId = expandedPersonId == person.id ? nil : person.id
                                        }
                                    },
                                    onSendEmail: {
                                        if vm.isUnlocked {
                                            Task {
                                                sendingEmailFor = person.id
                                                await vm.sendPersonEmail(personId: person.id)
                                                sendingEmailFor = nil
                                            }
                                        } else {
                                            vm.presentPaywall(context: "Unlock to send email summaries")
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

                            ForEach(vm.state.bills) { bill in
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

                        // MARK: Checklist Section

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.bhSurface3)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "checkmark")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.bhMuted)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Monthly Checklist")
                                        .font(.headline)
                                        .foregroundColor(.bhText)
                                    Text("Track what's been done this month")
                                        .font(.bhCaption)
                                        .foregroundColor(.bhMuted)
                                }
                            }

                            VStack(spacing: 0) {
                                let items = vm.checklistItems(for: vm.monthKey)
                                ForEach(items, id: \.id) { item in
                                    ChecklistItemRow(item: item) {
                                        vm.toggleChecklistItem(item.id, for: vm.monthKey)
                                    }
                                    if item.id != items.last?.id {
                                        Divider().background(Color.bhBorder)
                                    }
                                }
                            }
                            .bhCard()
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                }
                .refreshable { await vm.refresh() }
            }
            .navigationBarHidden(true)
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
    let onToggle: () -> Void
    let onSendEmail: () -> Void

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
                        Text(person.name)
                            .font(.bhBody)
                            .foregroundColor(.bhText)
                        Text(person.payMethod.displayName)
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                    }

                    Spacer()

                    Text((personOwes?.total ?? 0).asCurrency)
                        .font(.bhMoneyMedium)
                        .foregroundColor(Color(hex: person.color) ?? .bhAmber)

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

                    // Actions — email and payment request
                    HStack(spacing: 10) {
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
                        }
                        .buttonStyle(BHSecondaryButtonStyle())
                        .disabled(person.email.isEmpty || isSendingEmail)

                        if let url = payURL {
                            Link(destination: url) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                    Text("Request via \(payLabel)")
                                }
                                .font(.bhCaption.weight(.medium))
                                .foregroundColor(.bhText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(Color.bhSurface2)
                                .cornerRadius(7)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.bhBorder, lineWidth: 1))
                            }
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
                        Text(vm.getBillTotal(bill.id).asCurrency)
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
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
    }
}
