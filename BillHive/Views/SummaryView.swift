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
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary")
                                .font(.system(size: 18, weight: .bold, design: .default))
                                .foregroundColor(.bhText)
                            Text("What everyone owes this month — \(vm.monthLabel)")
                                .font(.system(size: 11, design: .default))
                                .foregroundColor(.bhMuted)
                        }
                        .padding(.top, 16)

                        // Person summary cards
                        let nonMePeople = vm.state.people.filter { $0.id != "me" }
                        if nonMePeople.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "person.2.slash")
                                    .font(.system(size: 28))
                                    .foregroundColor(.bhMuted)
                                Text("No people added yet.\nGo to Settings to add household members.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.bhMuted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
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
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.bhMuted)
                                        Spacer()
                                        Text(myShare.asCurrency)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.bhText)
                                    }
                                    .padding(.vertical, 8)
                                    Divider().background(Color.bhBorder)
                                }
                            }

                            HStack {
                                Text("Total I'm paying")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.bhMuted)
                                Spacer()
                                Text(myTotal.asCurrency)
                                    .font(.system(size: 22, weight: .bold, design: .monospaced))
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

// MARK: - Person Summary Card

/// A compact card displaying a single person's total owed amount and
/// the bill names contributing to that total, styled with the person's color.
struct PersonSummaryCard: View {
    let person: Person
    let personOwes: PersonOwes?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color(hex: person.color) ?? .bhAmber)
                    .frame(width: 10, height: 10)
                Text(person.name)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.bhText)
            }

            Text((personOwes?.total ?? 0).asCurrency)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: person.color) ?? .bhAmber)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if let bills = personOwes?.bills, !bills.isEmpty {
                Text(bills.map { $0.billName }.joined(separator: " · "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.bhMuted)
                    .lineLimit(2)
            } else {
                Text("Nothing owed")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.bhMuted2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            ZStack(alignment: .top) {
                Color.bhSurface2
                Rectangle()
                    .fill(Color(hex: person.color) ?? .bhAmber)
                    .frame(height: 3)
            }
        )
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.bhText)
                Spacer()
                Text(total.asCurrency)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
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
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.bhMuted)
                    }
                    Spacer()
                    Text(amount.asCurrency)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.bhText)
                }
                .padding(.vertical, 4)
                .padding(.leading, 12)
            }

            Divider().background(Color.bhBorder)
        }
    }
}
