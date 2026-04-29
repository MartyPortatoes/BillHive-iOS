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
                                HStack(spacing: 6) {
                                    Label("Add Bill", systemImage: "plus")
                                    if !vm.isUnlocked && vm.state.bills.count >= 2 {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                            .foregroundColor(.bhAmber)
                                    }
                                }
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
            .navigationBarHidden(true)
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
        if vm.isUnlocked || vm.state.bills.count < 2 {
            vm.addBill()
            if let last = vm.state.bills.last {
                withAnimation { expandedBillId = last.id }
                // Open the editor sheet for the new bill
                editingBillId = last.id
            }
        } else {
            vm.presentPaywall(context: "Unlock unlimited bills")
        }
    }
}

// MARK: - Month Picker Bar

/// Horizontal pill containing two `.menu`-style pickers for month and year.
/// Sits at the trailing edge of the bar; the inner pill background prevents
/// the pickers from expanding to fill available width.
struct MonthPickerBar: View {
    @EnvironmentObject var vm: AppViewModel
    private let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    private let years = Array(2020...2035)

    var body: some View {
        HStack(spacing: 6) {
            Spacer()
            HStack(spacing: 4) {
                Picker("Month", selection: $vm.selectedMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(months[m-1]).tag(m)
                    }
                }
                .pickerStyle(.menu)
                .tint(.bhText)
                .font(.bhBodySecondary)

                Picker("Year", selection: $vm.selectedYear) {
                    ForEach(years, id: \.self) { y in
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

    var total: Double { vm.getBillTotal(bill.id) }
    var myShare: Double { vm.computeBillSplit(bill)["me"] ?? 0 }

    private var splitDescription: String {
        bill.splitType == .pct ? "Splits by percent" : "Splits by amount"
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
                        Text(bill.name.isEmpty ? "Untitled bill" : bill.name)
                            .font(.bhBodyName)
                            .foregroundColor(.bhText)
                            .lineLimit(1)
                        Text(splitDescription)
                            .font(.bhBodyNameSecondary)
                            .foregroundColor(.bhMuted)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(total > 0 ? total.asCurrency : "$—")
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

// MARK: - Bill Editor Sheet

/// Full-screen editor for a bill's settings, presented as a sheet with a
/// navigation bar providing a clear "Done" affordance.
///
/// The read-only split preview lives on the bill card (slide-out), not
/// inside this editor — avoids duplicating the same information in two
/// places when the user is already in edit mode.
///
/// Uses the bill's `id` to look up its live index in the view model rather
/// than holding a stale `@Binding`, preventing index-out-of-bounds crashes
/// after array mutations.
struct BillEditorSheet: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill
    let onDone: () -> Void

    @State private var showRemoveConfirm = false
    @State private var showIconPicker = false

    /// Safely resolves the bill's current index on each render.
    private var billIndex: Int? {
        vm.state.bills.firstIndex(where: { $0.id == bill.id })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: Bill Identity (Icon, Name, Color)
                        HStack(spacing: 8) {
                            Button {
                                showIconPicker = true
                            } label: {
                                Text(bill.icon.isEmpty ? "💡" : bill.icon)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(Color(hex: bill.color)?.opacity(0.2) ?? Color.bhSurface2)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                            }
                            .accessibilityLabel("Choose icon")

                            TextField("Bill name", text: Binding(
                                get: { bill.name },
                                set: { val in
                                    guard let idx = billIndex else { return }
                                    vm.state.bills[idx].name = val
                                    vm.save()
                                }
                            ))
                            .font(.bhBodyName)
                            .foregroundColor(.bhText)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.bhSurface2)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))

                            ColorPicker("", selection: Binding(
                                get: { Color(hex: bill.color) ?? .bhAmber },
                                set: { newColor in
                                    guard let idx = billIndex, let hex = newColor.toHex() else { return }
                                    vm.state.bills[idx].color = hex
                                    vm.save()
                                }
                            ))
                            .labelsHidden()
                            .frame(width: 44, height: 44)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                        Divider().background(Color.bhBorder).padding(.horizontal, 16)

                        // MARK: Split Type Toggle
                        HStack(spacing: 8) {
                            Text("Split Type")
                                .font(.bhBodyName)
                                .foregroundColor(.bhMuted)
                            Spacer()
                            HStack(spacing: 0) {
                                ForEach(SplitType.allCases, id: \.self) { type in
                                    Button(type.displayName) {
                                        guard let idx = billIndex else { return }
                                        vm.state.bills[idx].splitType = type
                                        vm.save()
                                    }
                                    .font(.bhBodyName)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(bill.splitType == type ? Color.bhSurface3 : Color.clear)
                                    .foregroundColor(bill.splitType == type ? .bhAmber : .bhMuted)
                                    .cornerRadius(5)
                                }
                            }
                            .background(Color.bhSurface2)
                            .cornerRadius(7)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.bhBorder, lineWidth: 1))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        // MARK: Total Bill Input
                        HStack {
                            Text("Total Bill")
                                .font(.bhBodyName)
                                .foregroundColor(.bhMuted)
                            if bill.splitType == .fixed {
                                Text("Remainder → \(vm.state.people.first { $0.id == (bill.lines.first { $0.id == bill.remainderLineId }?.personId ?? "") }?.name ?? "—")")
                                    .font(.bhCaption)
                                    .foregroundColor(.bhMuted2)
                            }
                            Spacer()
                            CurrencyInputField(
                                value: Binding(
                                    get: { vm.getBillTotal(bill.id) },
                                    set: { vm.setBillTotal(bill.id, value: $0) }
                                )
                            )
                            .frame(width: 120)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.bhSurface2)
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                        Divider().background(Color.bhBorder).padding(.horizontal, 16)

                        // MARK: Line Items Header
                        HStack {
                            Text("Person").bhSectionTitle().frame(width: 100, alignment: .leading)
                            Spacer()
                            if bill.splitType == .pct {
                                Text("%").bhSectionTitle().frame(width: 50, alignment: .trailing)
                                Text("Amount").bhSectionTitle().frame(width: 80, alignment: .trailing)
                            } else {
                                Text("Amount").bhSectionTitle().frame(width: 80, alignment: .trailing)
                            }
                            Spacer().frame(width: 44)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                        // MARK: Line Items
                        ForEach(bill.lines) { line in
                            BillLineRowView(bill: bill, line: line)
                            Divider().background(Color.bhBorder).padding(.horizontal, 16)
                        }

                        Button {
                            vm.addLine(to: bill.id)
                        } label: {
                            Label("Add Person", systemImage: "plus")
                                .font(.bhBodyName)
                                .foregroundColor(.bhAmber)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().background(Color.bhBorder).padding(.horizontal, 16)

                        // MARK: Preserve Toggle
                        Toggle(isOn: Binding(
                            get: { bill.preserve },
                            set: { val in
                                guard let idx = billIndex else { return }
                                vm.state.bills[idx].preserve = val
                                vm.save()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-carry forward")
                                    .font(.bhBodyName)
                                    .foregroundColor(.bhText)
                                Text("Copy last month's amounts when switching months")
                                    .font(.bhCaption)
                                    .foregroundColor(.bhMuted)
                            }
                        }
                        .tint(.bhAmber)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Toggle(isOn: Binding(
                            get: { bill.autoPay },
                            set: { val in
                                guard let idx = billIndex else { return }
                                vm.state.bills[idx].autoPay = val
                                vm.save()
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-pay")
                                    .font(.bhBodyName)
                                    .foregroundColor(.bhText)
                                Text("Skip \"paid\" task in monthly checklist")
                                    .font(.bhCaption)
                                    .foregroundColor(.bhMuted)
                            }
                        }
                        .tint(.bhAmber)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().background(Color.bhBorder).padding(.horizontal, 16)

                        Button(role: .destructive) {
                            showRemoveConfirm = true
                        } label: {
                            Label("Remove Bill", systemImage: "trash")
                                .font(.bhBodyName)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(bill.name.isEmpty ? "Edit Bill" : bill.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
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
            .sheet(isPresented: $showIconPicker) {
                EmojiPickerSheet(selected: bill.icon) { newIcon in
                    guard let idx = billIndex else { return }
                    vm.state.bills[idx].icon = newIcon
                    vm.save()
                }
            }
            .confirmationDialog("Remove \"\(bill.name)\"?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
                Button("Remove Bill", role: .destructive) {
                    vm.removeBill(bill)
                    onDone()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove the bill and all its settings.")
            }
        }
        .bhColorScheme()
    }
}

// MARK: - Emoji Picker Sheet

/// A curated grid of common bill-related emoji shown as a small modal sheet.
/// Replaces the previous freeform `TextField` icon entry, which surfaced the
/// system emoji keyboard and was awkward on iOS.
struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selected: String
    let onSelect: (String) -> Void

    private let emojis: [String] = [
        "🏠", "🏡", "⚡️", "💡", "🔥", "💧", "🚿",
        "🌐", "📡", "📺", "📞", "📱", "💻", "🛜",
        "🚗", "⛽️", "🛞", "🚙", "🛡", "🩺", "💊",
        "🍔", "🛒", "🥦", "☕️", "🍷", "🎵", "🎮",
        "📚", "🎓", "🏋️", "🐶", "🐱", "🌱", "🧹",
        "💳", "💰", "📅", "📦", "✈️", "🏖", "☁️"
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(emojis, id: \.self) { emoji in
                            Button {
                                onSelect(emoji)
                                dismiss()
                            } label: {
                                Text(emoji)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(emoji == selected ? Color.bhAmber.opacity(0.2) : Color.bhSurface2)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(emoji == selected ? Color.bhAmber : Color.bhBorder, lineWidth: 1)
                                    )
                            }
                            .accessibilityLabel("Select \(emoji)")
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.bhAmber)
                }
            }
        }
        .bhColorScheme()
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Bill Line Row

/// A single line item within a bill's expanded body — shows the person picker,
/// percentage/amount input, "covered by" selector, and a remove button.
struct BillLineRowView: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill
    let line: BillLine

    private var billIndex: Int? { vm.state.bills.firstIndex { $0.id == bill.id } }
    private var lineIndex: Int? { bill.lines.firstIndex { $0.id == line.id } }

    /// The effective payer: coveredById if set, otherwise the line's own personId.
    private var effectivePayer: String { line.coveredById ?? line.personId }

    /// The computed dollar amount for this line in the current month.
    var computedAmount: Double {
        if bill.splitType == .pct {
            return vm.getBillTotal(bill.id) * line.value / 100.0
        } else if line.id == bill.remainderLineId {
            let others = bill.lines
                .filter { $0.id != bill.remainderLineId }
                .reduce(0.0) { $0 + vm.getLineAmount(bill.id, lineId: $1.id) }
            return max(0, vm.getBillTotal(bill.id) - others)
        } else {
            return vm.getLineAmount(bill.id, lineId: line.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row: person picker + amount
            HStack(spacing: 8) {
                Picker("", selection: Binding(
                    get: { line.personId },
                    set: { val in
                        guard let bi = billIndex, let li = lineIndex else { return }
                        vm.state.bills[bi].lines[li].personId = val
                        if vm.state.bills[bi].lines[li].coveredById == val {
                            vm.state.bills[bi].lines[li].coveredById = nil
                        }
                        vm.save()
                    }
                )) {
                    ForEach(vm.state.people) { person in
                        Text(person.name).tag(person.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.bhText)
                .font(.bhBodyName)
                .frame(width: 100)

                Spacer()

                if bill.splitType == .pct {
                    TextField("0", value: Binding(
                        get: { line.value },
                        set: { val in
                            vm.setLinePct(billId: bill.id, lineId: line.id, value: val)
                            vm.saveMonthSnapshot()
                        }
                    ), format: .number.precision(.fractionLength(0...2)))
                    .font(.bhBodySecondary)
                    .foregroundColor(.bhText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .frame(width: 50)
                    .background(Color.bhSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.bhBorder, lineWidth: 1))

                    Text(computedAmount.asCurrency)
                        .font(.bhMoneySmall)
                        .foregroundColor(.bhAmber)
                        .frame(width: 80, alignment: .trailing)
                } else {
                    if line.id == bill.remainderLineId {
                        Text(computedAmount.asCurrency)
                            .font(.bhMoneySmall)
                            .foregroundColor(.bhAmber)
                            .frame(width: 80, alignment: .trailing)
                    } else {
                        CurrencyInputField(
                            value: Binding(
                                get: { vm.getLineAmount(bill.id, lineId: line.id) },
                                set: { vm.setLineAmount(bill.id, lineId: line.id, value: $0) }
                            )
                        )
                        .frame(width: 80)
                    }
                }

                // 44pt hit area, smaller visual size
                Button {
                    vm.removeLine(billId: bill.id, lineId: line.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.bhMuted)
                        .frame(width: 24, height: 24)
                        .background(Color.bhSurface2)
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.bhBorder, lineWidth: 1))
                        .frame(width: 44, height: 44) // 44pt tap target
                        .contentShape(Rectangle())
                }
                .disabled(bill.lines.count <= 1)
                .opacity(bill.lines.count <= 1 ? 0.3 : 1)
                .accessibilityLabel("Remove line")
            }
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 5)

            // "Covered by" sub-row
            HStack(spacing: 6) {
                Text("Covered by")
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)

                Picker("", selection: Binding(
                    get: { effectivePayer },
                    set: { val in
                        guard let bi = billIndex, let li = lineIndex else { return }
                        let selfId = vm.state.bills[bi].lines[li].personId
                        vm.state.bills[bi].lines[li].coveredById = (val == selfId) ? nil : val
                        vm.save()
                    }
                )) {
                    ForEach(vm.state.people) { person in
                        Text(person.id == line.personId ? "\(person.name) (self)" : person.name)
                            .tag(person.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(line.coveredById != nil ? Color.bhAmber : .bhMuted)
                .font(.bhCaption)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 9)
        }
    }
}

// MARK: - Currency Input Field

/// A text field that displays and edits a dollar amount.
///
/// Shows the formatted value when unfocused and switches to raw text editing
/// when focused. Commits the parsed value on blur.
struct CurrencyInputField: View {
    @Binding var value: Double
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0.00", text: $text)
            .font(.bhBodySecondary.weight(.medium))
            .foregroundColor(.bhText)
            .multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
            .padding(6)
            .background(Color.bhSurface2)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? Color.bhAmber : Color.bhBorder, lineWidth: 1))
            .focused($focused)
            .onAppear {
                text = value > 0 ? String(format: "%.2f", value) : ""
            }
            .onChange(of: focused) { isFocused in
                if !isFocused {
                    value = Double(text) ?? 0
                }
            }
            .onChange(of: value) { newVal in
                if !focused {
                    text = newVal > 0 ? String(format: "%.2f", newVal) : ""
                }
            }
    }
}
