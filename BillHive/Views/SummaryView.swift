import SwiftUI

// MARK: - Summary View

/// Monthly summary screen showing what each household member owes and
/// a full per-bill breakdown with the primary user's total outlay.
struct SummaryView: View {
    @EnvironmentObject var vm: AppViewModel

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
                        MonthPickerBar()
                            .padding(.top, 12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary")
                                .font(.bhViewTitle)
                                .foregroundColor(.bhText)
                            Text("What everyone owes this month — \(vm.monthLabel)")
                                .font(.bhSubtitle)
                                .foregroundColor(.bhMuted)
                        }

                        if vm.state.bills.isEmpty {
                            EmptyStateView(
                                systemImage: "dollarsign.circle",
                                title: "Nothing to summarize yet",
                                subtitle: "Add your first bill in the Bills tab and the monthly split will appear here."
                            )
                        } else {
                            summaryContent
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
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(nonMePeople.filter { (owes[$0.id]?.total ?? 0) > 0 }) { person in
                    PersonSummaryCard(
                        person: person,
                        personOwes: owes[person.id]
                    )
                }
            }
        }

        // My outlay card
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("My Total Outlay")
                    .bhSectionTitle()
                Spacer()
            }
            .padding(.bottom, 12)

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
        }
        .padding(16)
        .bhCard()

        // Full breakdown
        VStack(alignment: .leading, spacing: 0) {
            Text("Full Bill Breakdown")
                .bhSectionTitle()
                .padding(.bottom, 12)

            ForEach(vm.state.bills) { bill in
                FullBreakdownRow(bill: bill)
            }
        }
        .padding(16)
        .bhCard()
    }
}

// MARK: - Person Summary Card

/// A compact card displaying a single person's total owed amount and
/// the bill names contributing to that total, styled with the person's color.
struct PersonSummaryCard: View {
    let person: Person
    let personOwes: PersonOwes?

    var body: some View {
        HStack(spacing: 0) {
            // Left-edge color stripe (more iOS-native than top stripe)
            Rectangle()
                .fill(Color(hex: person.color) ?? .bhAmber)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(person.name)
                    .font(.bhBodyName)
                    .foregroundColor(.bhText)

                Text((personOwes?.total ?? 0).asCurrency)
                    .font(.bhMoneyLarge)
                    .foregroundColor(Color(hex: person.color) ?? .bhAmber)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                if let bills = personOwes?.bills, !bills.isEmpty {
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
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bhBorder, lineWidth: 1))
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
