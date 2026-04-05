import SwiftUI

// MARK: - Send & Receive View

/// Central hub for collecting payments and paying bills.
///
/// Three sections:
/// - **Receive** — shows each person who owes money with expandable details and
///   email/payment-app actions.
/// - **Send** — lists every bill with an optional payment URL and a "Pay" button.
/// - **Checklist** — per-month task checklist for tracking what's been done.
struct SendReceiveView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var expandedPersonId: String? = nil
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Send & Receive")
                                .font(.system(size: 18, weight: .bold, design: .default))
                                .foregroundColor(.bhText)
                            Text("Collect from others and pay your bills.")
                                .font(.system(size: 11, design: .default))
                                .foregroundColor(.bhMuted)
                        }
                        .padding(.top, 16)

                        // MARK: Receive Section

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.bhBlue.opacity(0.15))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBlue.opacity(0.25), lineWidth: 1))
                                        .frame(width: 32, height: 32)
                                    Text("↓")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.bhBlue)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Receive")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(.bhText)
                                    Text("Notify people what they owe and request payment")
                                        .font(.system(size: 11, design: .monospaced))
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

                        // MARK: Send Section

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.bhAmber.opacity(0.15))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhAmber.opacity(0.25), lineWidth: 1))
                                        .frame(width: 32, height: 32)
                                    Text("↑")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.bhAmber)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Send")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(.bhText)
                                    Text("Pay your bills — tap Pay on any bill with a URL")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.bhMuted)
                                }
                            }

                            ForEach(vm.state.bills) { bill in
                                SendCard(bill: bill)
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
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.bhMuted)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Monthly Checklist")
                                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                                        .foregroundColor(.bhText)
                                    Text("Track what's been done this month")
                                        .font(.system(size: 11, design: .monospaced))
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

/// An expandable card for a single person in the Receive section.
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
    var zelleURL: URL? {
        if let zu = person.zelleUrl, !zu.isEmpty { return URL(string: zu) }
        if person.payMethod == .zelle, !person.payId.isEmpty {
            let encoded = person.payId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return URL(string: "https://enroll.zellepay.com/qr-codes?data=\(encoded)")
        }
        return nil
    }

    /// Constructs a Venmo deep link with the charge amount pre-filled.
    var venmoURL: URL? {
        guard person.payMethod == .venmo, !person.payId.isEmpty else { return nil }
        let handle = person.payId.hasPrefix("@") ? String(person.payId.dropFirst()) : person.payId
        let amount = personOwes?.total ?? 0
        let note = "Bills"
        let encoded = note.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Bills"
        return URL(string: "venmo://paycharge?txn=charge&recipients=\(handle)&amount=\(String(format: "%.2f", amount))&note=\(encoded)")
    }

    /// Constructs a Cash App profile URL from the person's cashtag.
    var cashAppURL: URL? {
        guard person.payMethod == .cashapp, !person.payId.isEmpty else { return nil }
        let tag = person.payId.hasPrefix("$") ? person.payId : "$\(person.payId)"
        return URL(string: "https://cash.app/\(tag)")
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
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.bhText)
                        Text(person.payMethod.displayName)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.bhMuted)
                    }

                    Spacer()

                    Text((personOwes?.total ?? 0).asCurrency)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: person.color) ?? .bhAmber)

                    HStack(spacing: 6) {
                        // Payment button
                        if let url = payURL {
                            Link(destination: url) {
                                Text(payLabel)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(hex: "#0c0d0f"))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color(hex: person.color) ?? .bhAmber)
                                    .cornerRadius(6)
                            }
                        }

                        Button(action: onToggle) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .medium))
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
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.bhMuted)
                            Spacer()
                            Text(bo.amount.asCurrency)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                                        .font(.system(size: 11))
                                }
                                Text(isSendingEmail ? "Sending..." : "Send Email")
                            }
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .buttonStyle(BHSecondaryButtonStyle())
                        .disabled(person.email.isEmpty || isSendingEmail)

                        if let url = payURL {
                            Link(destination: url) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 11))
                                    Text("Request via \(payLabel)")
                                }
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
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

/// A card for a single bill in the Send section, showing the bill total
/// and an editable payment URL field with a "Pay" link button.
struct SendCard: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill

    /// Safely looks up the bill's current array index each time.
    private var billIndex: Int? { vm.state.bills.firstIndex(where: { $0.id == bill.id }) }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Main Row

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(hex: bill.color)?.opacity(0.2) ?? Color.bhSurface3)
                        .frame(width: 34, height: 34)
                    Text(bill.icon).font(.system(size: 16))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.name)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.bhText)
                    Text(vm.getBillTotal(bill.id).asCurrency)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.bhMuted)
                }

                Spacer()

                if !bill.payUrl.isEmpty, let url = URL(string: bill.payUrl) {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                            Text("Pay")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(Color(hex: "#0c0d0f"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.bhAmber)
                        .cornerRadius(7)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.bhBorder)

            // MARK: Pay URL Field

            HStack(spacing: 8) {
                Text("Pay URL")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundColor(.bhMuted)
                    .frame(width: 60, alignment: .leading)

                TextField("https://your-bank.com/pay", text: Binding(
                    get: { bill.payUrl },
                    set: { val in
                        guard let idx = billIndex else { return }
                        vm.state.bills[idx].payUrl = val
                        vm.save()
                    }
                ))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.bhText)
                .textFieldStyle(.plain)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                if !bill.payUrl.isEmpty, let url = URL(string: bill.payUrl) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14))
                            .foregroundColor(.bhAmber)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.bhSurface2)
        }
        .background(Color.bhSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bhBorder, lineWidth: 1))
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
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#0c0d0f"))
                    }
                }

                Text(item.label)
                    .font(.system(size: 12, design: .monospaced))
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
