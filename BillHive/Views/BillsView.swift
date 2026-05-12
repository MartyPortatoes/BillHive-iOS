import SwiftUI

// MARK: - Bills View

/// The main bills management screen — a list of expandable bill cards.
/// Tapping a card reveals a read-only per-person split preview; tapping
/// the "Edit Bill" button inside opens the full editor sheet.
///
/// The month picker is a pill bar at the top of the content (above the
/// title), keeping month + year selection close to where they're consumed.
struct BillsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var expandedBillId: String? = nil
    @State private var editingBillId: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                HexBGView().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        MonthPickerBar()
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                        VStack(spacing: 1) {
                            Text("Bills")
                                .font(.bhViewTitle)
                                .foregroundColor(.bhText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 4)

                            Text("Add your bills and configure who owes what.")
                                .font(.bhSubtitle)
                                .foregroundColor(.bhMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }

                        if vm.state.bills.isEmpty {
                            EmptyStateView(
                                systemImage: "list.clipboard",
                                title: "No bills yet",
                                subtitle: "Add your first recurring household bill to start tracking who owes what each month.",
                                actionTitle: "Add Your First Bill",
                                action: addBillAction
                            )
                            .padding(.top, 12)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(vm.state.bills) { bill in
                                    BillCardView(
                                        bill: bill,
                                        isExpanded: expandedBillId == bill.id,
                                        onToggle: {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                expandedBillId = expandedBillId == bill.id ? nil : bill.id
                                            }
                                        },
                                        onEdit: { editingBillId = bill.id }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)

                            Button(action: addBillAction) {
                                Label("Add Bill", systemImage: "plus")
                            }
                            .buttonStyle(BHSecondaryButtonStyle())
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .refreshable { await vm.refresh() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.bhAmber)
                }
            }
            .sheet(isPresented: Binding(
                get: { editingBillId != nil },
                set: { if !$0 { editingBillId = nil } }
            )) {
                if let id = editingBillId,
                   let bill = vm.state.bills.first(where: { $0.id == id }) {
                    BillEditorSheet(bill: bill) { editingBillId = nil }
                        .environmentObject(vm)
                }
            }
        }
    }

    private func addBillAction() {
        vm.addBill()
        if let last = vm.state.bills.last {
            withAnimation { expandedBillId = last.id }
            editingBillId = last.id
        }
    }
}

// MARK: - Month Picker Bar

/// Horizontal pill containing two `.menu`-style pickers for month and year.
/// Sits at the trailing edge of the bar; the inner pill background prevents
/// the pickers from expanding to fill available width.
struct MonthPickerBar: View {
    @EnvironmentObject var vm: AppViewModel
    private static let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    private static let years = Array(2020...2035)

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
            HStack(spacing: 4) {
                Picker("Month", selection: $vm.selectedMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(Self.months[m-1]).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .tint(.bhText)
                .font(.bhBodySecondary)

                Picker("Year", selection: $vm.selectedYear) {
                    ForEach(Self.years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.menu)
                .tint(.bhText)
                .font(.bhBodySecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.bhSurface2)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
        }
        .onChange(of: vm.selectedMonth) { _ in vm.onMonthChange() }
        .onChange(of: vm.selectedYear) { _ in vm.onMonthChange() }
    }
}

// MARK: - Bill Card (Collapsed Header + Read-only Preview)

/// An expandable card showing a bill's header (icon, name, total, your share)
/// and, when expanded, a read-only per-person split preview with an Edit button.
///
/// Full editing is delegated to `BillEditorSheet` via the `onEdit` callback.
struct BillCardView: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill
    let isExpanded: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var total: Double { vm.getBillTotal(bill.id) }
    private var myShare: Double { vm.computeBillSplit(bill)["me"] ?? 0 }

    private var splitDescription: String {
        bill.splitType == .pct ? "Splits by percent" : "Splits by amount"
    }

    /// Color for the due-day badge based on urgency.
    private var dueBadgeColor: Color {
        switch bill.dueUrgency(month: vm.selectedMonth, year: vm.selectedYear) {
        case .overdue: return .bhRed
        case .soon: return .bhAmber
        default: return .bhMuted
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row — always visible, tap toggles the read-only preview
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: bill.color)?.opacity(0.2) ?? Color.bhSurface3)
                            .frame(width: 38, height: 38)
                        Text(bill.icon)
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(bill.name.isEmpty ? "Untitled bill" : bill.name)
                                .font(.bhBodyName)
                                .foregroundColor(.bhText)
                                .lineLimit(1)

                            if let label = bill.dueDayLabel {
                                Text("Due \(label)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(dueBadgeColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(dueBadgeColor.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                        Text(splitDescription)
                            .font(.bhBodyNameSecondary)
                            .foregroundColor(.bhMuted)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(total > 0 ? total.asCurrency : "\(CurrencyManager.symbol)—")
                            .font(.bhMoneyMedium)
                            .foregroundColor(total > 0 ? .bhAmber : .bhMuted)
                        Text("your share \(myShare.asCurrency)")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.bhMuted)
                        .frame(width: 20)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(bill.name), total \(total.asCurrency), your share \(myShare.asCurrency)")
            .accessibilityHint(isExpanded ? "Collapse preview" : "Expand preview")

            if isExpanded {
                Divider().background(Color.bhBorder)
                BillPreviewView(bill: bill, onEdit: onEdit)
            }
        }
        .background(Color.bhSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isExpanded ? Color.bhBorder2 : Color.bhBorder, lineWidth: 1))
    }
}

// MARK: - Bill Preview (Read-only Split + Edit CTA)

/// The expanded read-only preview of a bill card — shows the per-person split
/// for the current month along with an "Edit Bill" button that opens the full
/// editor sheet.
struct BillPreviewView: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill
    let onEdit: () -> Void

    var body: some View {
        let split = vm.computeBillSplit(bill)
        let contributingPeople = vm.state.people.filter { (split[$0.id] ?? 0) > 0 }

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Split this month")
                    .bhSectionTitle()
                Spacer()
                if bill.preserve {
                    Text("Auto-carry forward")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if contributingPeople.isEmpty {
                Text("No amounts set for this month yet. Tap Edit to configure the split.")
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                ForEach(contributingPeople) { person in
                    let amount = split[person.id] ?? 0
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: person.color) ?? .gray)
                            .frame(width: 8, height: 8)
                        Text(person.name)
                            .font(.bhBodyNameSecondary)
                            .foregroundColor(.bhText)
                        Spacer()
                        Text(amount.asCurrency)
                            .font(.bhMoneySmall)
                            .foregroundColor(.bhText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
                .padding(.bottom, 4)
            }

            Divider().background(Color.bhBorder).padding(.horizontal, 16)

            Button(action: onEdit) {
                Label("Edit Bill", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BHSecondaryButtonStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// Bill editor sheet views are defined in BillEditorSheet.swift
