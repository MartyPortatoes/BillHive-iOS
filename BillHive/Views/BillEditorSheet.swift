import SwiftUI

// MARK: - Bill Editor Sheet

/// Full-screen editor for a bill's settings, presented as a sheet.
///
/// Accepts only a `billId` and reads all data live from the view model on
/// every render — never holds a stale value-type snapshot of `Bill`.
struct BillEditorSheet: View {
    @EnvironmentObject var vm: AppViewModel
    let billId: String
    let onDone: () -> Void

    @State private var showRemoveConfirm = false
    @State private var showIconPicker = false

    private var billIndex: Int? {
        vm.state.bills.firstIndex(where: { $0.id == billId })
    }

    private var bill: Bill? {
        guard let idx = billIndex else { return nil }
        return vm.state.bills[idx]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                if let bill = bill {
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
                                    set: { val in vm.updateBill(billId, affectsTotals: false) { $0.name = val } }
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
                                        guard let hex = newColor.toHex() else { return }
                                        vm.updateBill(billId, affectsTotals: false) { $0.color = hex }
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
                                            vm.updateBill(billId) { $0.splitType = type }
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

                            // MARK: Paid By
                            HStack {
                                Text("Paid By")
                                    .font(.bhBodyName)
                                    .foregroundColor(.bhMuted)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { bill.paidById },
                                    set: { val in vm.updateBill(billId) { $0.paidById = val } }
                                )) {
                                    ForEach(vm.state.people) { person in
                                        Text(person.isMe ? "\(person.name) (you)" : person.name).tag(person.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.bhAmber)
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
                                        get: { vm.getBillTotal(billId) },
                                        set: { vm.setBillTotal(billId, value: $0) }
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
                                BillLineRowView(billId: billId, lineId: line.id)
                                Divider().background(Color.bhBorder).padding(.horizontal, 16)
                            }

                            Button {
                                vm.addLine(to: billId)
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
                                set: { val in vm.updateBill(billId, affectsTotals: false) { $0.preserve = val } }
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
                                set: { val in vm.updateBill(billId, affectsTotals: false) { $0.autoPay = val } }
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

                            // Due day picker
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Due Day")
                                        .font(.bhBodyName)
                                        .foregroundColor(.bhText)
                                    Text("Day of the month this bill is due")
                                        .font(.bhCaption)
                                        .foregroundColor(.bhMuted)
                                }
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { bill.dueDay ?? 0 },
                                    set: { val in
                                        vm.updateBill(billId, affectsTotals: false) { $0.dueDay = val == 0 ? nil : val }
                                    }
                                )) {
                                    Text("None").tag(0)
                                    ForEach(1...31, id: \.self) { day in
                                        Text("\(day)").tag(day)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.bhAmber)
                            }
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
            }
            .navigationTitle(bill?.name.isEmpty == false ? bill!.name : "Edit Bill")
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
                EmojiPickerSheet(selected: bill?.icon ?? "") { newIcon in
                    vm.updateBill(billId, affectsTotals: false) { $0.icon = newIcon }
                }
            }
            .confirmationDialog("Remove \"\(bill?.name ?? "")\"?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
                Button("Remove Bill", role: .destructive) {
                    if let b = bill { vm.removeBill(b) }
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

/// A single line item within a bill editor. Reads all data live from the
/// view model via `billId` + `lineId` — never holds stale value copies.
struct BillLineRowView: View {
    @EnvironmentObject var vm: AppViewModel
    let billId: String
    let lineId: String

    private var billIndex: Int? { vm.state.bills.firstIndex { $0.id == billId } }

    private var bill: Bill? {
        guard let bi = billIndex else { return nil }
        return vm.state.bills[bi]
    }

    private var lineIndex: Int? {
        guard let bi = billIndex else { return nil }
        return vm.state.bills[bi].lines.firstIndex { $0.id == lineId }
    }

    private var line: BillLine? {
        guard let bi = billIndex, let li = lineIndex else { return nil }
        return vm.state.bills[bi].lines[li]
    }

    private var effectivePayer: String {
        guard let line = line else { return "" }
        return line.coveredById ?? line.personId
    }

    var computedAmount: Double {
        guard let bill = bill, let line = line else { return 0 }
        if bill.splitType == .pct {
            return vm.pctLineAmount(bill: bill, line: line, total: vm.getBillTotal(billId))
        } else if lineId == bill.remainderLineId {
            let others = bill.lines
                .filter { $0.id != bill.remainderLineId }
                .reduce(0.0) { $0 + vm.getLineAmount(billId, lineId: $1.id) }
            return max(0, vm.getBillTotal(billId) - others)
        } else {
            return vm.getLineAmount(billId, lineId: lineId)
        }
    }

    var body: some View {
        if let bill = bill, let line = line, let bi = billIndex, let li = lineIndex {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Picker("", selection: Binding(
                        get: { vm.state.bills[bi].lines[li].personId },
                        set: { val in
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
                            get: { vm.state.bills[bi].lines[li].value },
                            set: { val in
                                vm.setLinePct(billId: billId, lineId: lineId, value: val)
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
                        if lineId == bill.remainderLineId {
                            Text(computedAmount.asCurrency)
                                .font(.bhMoneySmall)
                                .foregroundColor(.bhAmber)
                                .frame(width: 80, alignment: .trailing)
                        } else {
                            CurrencyInputField(
                                value: Binding(
                                    get: { vm.getLineAmount(billId, lineId: lineId) },
                                    set: { vm.setLineAmount(billId, lineId: lineId, value: $0) }
                                )
                            )
                            .frame(width: 80)
                        }
                    }

                    Button {
                        vm.removeLine(billId: billId, lineId: lineId)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.bhMuted)
                            .frame(width: 24, height: 24)
                            .background(Color.bhSurface2)
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.bhBorder, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(bill.lines.count <= 1)
                    .opacity(bill.lines.count <= 1 ? 0.3 : 1)
                    .accessibilityLabel("Remove line")
                }
                .padding(.horizontal, 16)
                .padding(.top, 9)
                .padding(.bottom, 5)

                HStack(spacing: 6) {
                    Text("Covered by")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted)

                    Picker("", selection: Binding(
                        get: { effectivePayer },
                        set: { val in
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
}

// MARK: - Currency Input Field

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
