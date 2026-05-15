import SwiftUI

// MARK: - Summary View Mode

/// Segmented control options for the Summary tab.
enum SummaryViewMode: String, CaseIterable {
    case summary = "Summary"
    case checklist = "Checklist"
}

// MARK: - Summary View

/// Monthly summary screen showing what each household member owes and
/// a full per-bill breakdown with the primary user's total outlay.
/// Supports two modes via a segmented picker: "Summary" (financial
/// overview) and "Checklist" (monthly to-do tracking).
struct SummaryView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var viewMode: SummaryViewMode = .summary
    @State private var showFullBreakdown = false
    @State private var showMyOutlay = true
    @State private var showBetweenOthers = false

    /// Per-person owed amounts for the current month, keyed by person ID.
    var owes: [String: PersonOwes] { vm.computePersonOwes() }
    /// Total amount the primary user ("me") is paying this month.
    var myTotal: Double { vm.computeMyTotal() }

    var body: some View {
        NavigationStack {
            ZStack {
                HexBGView().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Summary")
                                .font(.title.weight(.bold))
                                .foregroundColor(.bhText)
                            Spacer()
                            MonthPickerBar()
                        }
                        .padding(.top, 12)

                        Text(viewMode == .summary
                             ? "What everyone owes this month — \(vm.monthLabel)"
                             : "Track your monthly to-dos — \(vm.monthLabel)")
                            .font(.bhSubtitle)
                            .foregroundColor(.bhMuted)

                        Picker("View", selection: $viewMode.animation(.easeInOut(duration: 0.2))) {
                            ForEach(SummaryViewMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if vm.state.bills.isEmpty {
                            EmptyStateView(
                                systemImage: "dollarsign.circle",
                                title: "Nothing to summarize yet",
                                subtitle: "Add your first bill in the Bills tab and the monthly split will appear here."
                            )
                        } else {
                            switch viewMode {
                            case .summary:
                                summaryContent
                            case .checklist:
                                checklistContent
                            }
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

    @ViewBuilder
    private var summaryContent: some View {
        // Person summary cards
        let nonMePeople = vm.state.people.filter { $0.id != "me" }
        if nonMePeople.isEmpty {
            EmptyStateView(
                systemImage: "person.2",
                title: "No people added yet",
                subtitle: "Go to Settings to add household members who'll share your bills."
            )
        } else {
            // Payment collection progress — at the top for quick status
            let owingPeople = nonMePeople.filter { (owes[$0.id]?.total ?? 0) > 0 }
            if !owingPeople.isEmpty {
                let paidCount = owingPeople.filter { vm.isPaymentReceived($0.id, for: vm.monthKey) }.count
                HStack(spacing: 10) {
                    Image(systemName: paidCount == owingPeople.count ? "checkmark.seal.fill" : "clock")
                        .font(.subheadline)
                        .foregroundColor(paidCount == owingPeople.count ? .bhGreen : .bhAmber)

                    Text("\(paidCount) of \(owingPeople.count) \(owingPeople.count == 1 ? "person has" : "people have") paid")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)

                    Spacer()

                    // Progress dots
                    HStack(spacing: 4) {
                        ForEach(owingPeople) { person in
                            Circle()
                                .fill(vm.isPaymentReceived(person.id, for: vm.monthKey) ? Color.bhGreen : Color.bhBorder2)
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(paidCount == owingPeople.count ? Color.bhGreen.opacity(0.08) : Color.bhSurface2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(paidCount == owingPeople.count ? Color.bhGreen.opacity(0.2) : Color.bhBorder, lineWidth: 1)
                        )
                )
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(nonMePeople.filter { (owes[$0.id]?.total ?? 0) > 0 }) { person in
                    PersonSummaryCard(
                        person: person,
                        personOwes: owes[person.id],
                        isPaymentReceived: vm.isPaymentReceived(person.id, for: vm.monthKey)
                    )
                }
            }

            // "You Owe" section — people with negative net balance
            let youOwePeople = nonMePeople.filter { (owes[$0.id]?.total ?? 0) < 0 }
            if !youOwePeople.isEmpty {
                Text("You Owe")
                    .bhSectionTitle()
                    .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(youOwePeople) { person in
                        let isPaid = vm.state.checklist[vm.monthKey]?["payback_\(person.id)"] ?? false
                        YouOweSummaryCard(person: person, amount: abs(owes[person.id]?.total ?? 0), bills: owes[person.id]?.bills ?? [], isPaid: isPaid)
                    }
                }
            }
        }

        // Between Others — collapsible, third-party settlements
        let settlements = vm.computeThirdPartySettlements()
        if !settlements.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showBetweenOthers.toggle()
                    }
                } label: {
                    HStack {
                        Text("Between Others")
                            .bhSectionTitle()
                        Spacer()
                        Text("\(settlements.count) \(settlements.count == 1 ? "settlement" : "settlements")")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted2)
                            .padding(.trailing, 6)
                        Image(systemName: showBetweenOthers ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.bhMuted2)
                    }
                }
                .buttonStyle(.plain)

                if showBetweenOthers {
                    ForEach(settlements) { settlement in
                        let fromPerson = vm.getPerson(settlement.fromId)
                        let toPerson = vm.getPerson(settlement.toId)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: fromPerson?.color ?? "") ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(fromPerson?.name ?? "?")
                                .font(.bhBodyName)
                                .foregroundColor(.bhMuted)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.bhMuted2)
                            Circle()
                                .fill(Color(hex: toPerson?.color ?? "") ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(toPerson?.name ?? "?")
                                .font(.bhBodyName)
                                .foregroundColor(.bhMuted)
                            Spacer()
                            Text(settlement.amount.asCurrency)
                                .font(.bhMoneySmall)
                                .foregroundColor(.bhText)
                        }
                        .padding(.vertical, 8)
                        Divider().background(Color.bhBorder)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundColor(.bhMuted2)
                        Text("Settlements between other household members — not involving you.")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted2)
                    }
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .bhCard()
        }

        // My outlay card — collapsible
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showMyOutlay.toggle()
                }
            } label: {
                HStack {
                    Text("My Total Outlay")
                        .bhSectionTitle()
                    Spacer()
                    Text(myTotal.asCurrency)
                        .font(.bhMoneyMedium)
                        .foregroundColor(.bhAmber)
                        .padding(.trailing, 6)
                    Image(systemName: showMyOutlay ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.bhMuted2)
                }
            }
            .buttonStyle(.plain)

            if showMyOutlay {
                ForEach(vm.state.bills) { bill in
                    let split = vm.computeBillSplit(bill)
                    let myShare = split["me"] ?? 0
                    if myShare > 0 {
                        HStack {
                            Text("\(bill.icon) \(bill.name)")
                                .font(.bhBodyName)
                                .foregroundColor(.bhMuted)
                            Spacer()
                            Text(myShare.asCurrency)
                                .font(.bhMoneySmall)
                                .foregroundColor(.bhText)
                        }
                        .padding(.vertical, 8)
                        Divider().background(Color.bhBorder)
                    }
                }

                HStack {
                    Text("Total I'm paying")
                        .font(.bhBodyName)
                        .foregroundColor(.bhMuted)
                    Spacer()
                    Text(myTotal.asCurrency)
                        .font(.bhMoneyLarge)
                        .foregroundColor(.bhAmber)
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .bhCard()

        // Full breakdown — collapsible
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showFullBreakdown.toggle()
                }
            } label: {
                HStack {
                    Text("Full Bill Breakdown")
                        .bhSectionTitle()
                    Spacer()
                    Image(systemName: showFullBreakdown ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.bhMuted2)
                }
            }
            .buttonStyle(.plain)

            if showFullBreakdown {
                ForEach(vm.state.bills) { bill in
                    FullBreakdownRow(bill: bill)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .bhCard()

    }

    // MARK: - Checklist Content

    @ViewBuilder
    private var checklistContent: some View {
        let items = vm.checklistItems(for: vm.monthKey)

        if items.isEmpty {
            EmptyStateView(
                systemImage: "checklist",
                title: "No checklist items",
                subtitle: "Add people and bills to generate your monthly checklist."
            )
        } else {
            // Progress header
            let doneCount = items.filter(\.done).count
            HStack(spacing: 10) {
                Image(systemName: doneCount == items.count ? "checkmark.seal.fill" : "checklist")
                    .font(.subheadline)
                    .foregroundColor(doneCount == items.count ? .bhGreen : .bhAmber)

                Text("\(doneCount) of \(items.count) completed")
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)

                Spacer()

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.bhBorder)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(doneCount == items.count ? Color.bhGreen : Color.bhAmber)
                            .frame(width: geo.size.width * CGFloat(doneCount) / CGFloat(max(items.count, 1)), height: 6)
                    }
                }
                .frame(width: 80, height: 6)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(doneCount == items.count ? Color.bhGreen.opacity(0.08) : Color.bhSurface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(doneCount == items.count ? Color.bhGreen.opacity(0.2) : Color.bhBorder, lineWidth: 1)
                    )
            )

            // Checklist items
            VStack(spacing: 0) {
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
    }
}

// MARK: - Person Summary Card

/// A compact card displaying a single person's total owed amount and
/// the bill names contributing to that total, styled with the person's color.
struct PersonSummaryCard: View {
    let person: Person
    let personOwes: PersonOwes?
    var isPaymentReceived: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Left-edge color stripe (more iOS-native than top stripe)
            Rectangle()
                .fill(isPaymentReceived ? Color.bhGreen : (Color(hex: person.color) ?? .bhAmber))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.bhBodyName)
                        .foregroundColor(.bhText)
                    if isPaymentReceived {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.bhGreen)
                    }
                }

                Text((personOwes?.total ?? 0).asCurrency)
                    .font(.bhMoneyLarge)
                    .foregroundColor(isPaymentReceived ? .bhMuted : (Color(hex: person.color) ?? .bhAmber))
                    .strikethrough(isPaymentReceived, color: .bhMuted)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if isPaymentReceived {
                    Text("Payment received")
                        .font(.bhCaption)
                        .foregroundColor(.bhGreen.opacity(0.8))
                } else if let bills = personOwes?.bills, !bills.isEmpty {
                    Text(bills.map { $0.billName }.joined(separator: " · "))
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)
                        .lineLimit(2)
                } else {
                    Text("Nothing owed")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Color.bhSurface2)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isPaymentReceived ? Color.bhGreen.opacity(0.3) : Color.bhBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(person.name) owes \((personOwes?.total ?? 0).asCurrency)\(isPaymentReceived ? ", paid" : "")")
    }
}

// MARK: - You Owe Summary Card

struct YouOweSummaryCard: View {
    let person: Person
    let amount: Double
    let bills: [BillOwed]
    var isPaid: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isPaid ? Color.bhGreen : Color.bhRed)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.bhBodyName)
                        .foregroundColor(.bhText)
                    if isPaid {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.bhGreen)
                    }
                }

                Text(amount.asCurrency)
                    .font(.bhMoneyLarge)
                    .foregroundColor(isPaid ? .bhMuted : .bhRed)
                    .strikethrough(isPaid, color: .bhMuted)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if isPaid {
                    Text("Paid")
                        .font(.bhCaption)
                        .foregroundColor(.bhGreen.opacity(0.8))
                } else if !bills.isEmpty {
                    Text(bills.map { $0.billName }.joined(separator: " · "))
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Color.bhSurface2)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isPaid ? Color.bhGreen.opacity(0.3) : Color.bhRed.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You owe \(person.name) \(amount.asCurrency)\(isPaid ? ", paid" : "")")
    }
}

// MARK: - Full Breakdown Row

/// Displays a single bill's total and per-person split in the
/// "Full Bill Breakdown" section.
struct FullBreakdownRow: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill

    var body: some View {
        let split = vm.computeBillSplit(bill)
        let total = vm.getBillTotal(bill.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(bill.icon) \(bill.name)")
                    .font(.bhBodyName)
                    .foregroundColor(.bhText)
                Spacer()
                Text(total.asCurrency)
                    .font(.bhMoneySmall)
                    .foregroundColor(.bhAmber)
            }
            .padding(.vertical, 10)

            ForEach(vm.state.people.filter { (split[$0.id] ?? 0) > 0 }) { person in
                let amount = split[person.id] ?? 0
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: person.color) ?? .gray)
                            .frame(width: 6, height: 6)
                        Text(person.name)
                            .font(.bhBodyName)
                            .foregroundColor(.bhMuted)
                    }
                    Spacer()
                    Text(amount.asCurrency)
                        .font(.bhMoneySmall)
                        .foregroundColor(.bhText)
                }
                .padding(.vertical, 4)
                .padding(.leading, 12)
            }

            Divider().background(Color.bhBorder)
        }
    }
}
