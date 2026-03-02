import SwiftUI

struct BillsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var expandedBillId: String? = nil

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
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(.bhText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 4)

                            Text("Add your bills and configure who owes what.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.bhMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }

                        LazyVStack(spacing: 10) {
                            ForEach(vm.state.bills) { bill in
                                BillCardView(
                                    bill: bill,
                                    isExpanded: expandedBillId == bill.id,
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            expandedBillId = expandedBillId == bill.id ? nil : bill.id
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)

                        Button {
                            vm.addBill()
                            if let last = vm.state.bills.last {
                                withAnimation {
                                    expandedBillId = last.id
                                }
                            }
                        } label: {
                            Label("Add Bill", systemImage: "plus")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .buttonStyle(BHSecondaryButtonStyle())
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .refreshable { await vm.refresh() }
            }
            .navigationBarHidden(true)
        }
    }
}

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
                .font(.system(size: 12, design: .monospaced))

                Picker("Year", selection: $vm.selectedYear) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.menu)
                .tint(.bhText)
                .font(.system(size: 12, design: .monospaced))
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

struct BillCardView: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill
    let isExpanded: Bool
    let onToggle: () -> Void

    var total: Double { vm.getBillTotal(bill.id) }
    var myShare: Double { vm.computeBillSplit(bill)["me"] ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(hex: bill.color)?.opacity(0.2) ?? Color.bhSurface3)
                            .frame(width: 34, height: 34)
                        Text(bill.icon)
                            .font(.system(size: 16))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(bill.name.uppercased())
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundColor(.bhText)
                        Text(bill.splitType == .pct ? "% split" : "Fixed split")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.bhMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(total > 0 ? total.asCurrency : "$—")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundColor(total > 0 ? .bhAmber : .bhMuted)
                        Text("my share \(myShare.asCurrency)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.bhMuted)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.bhMuted)
                        .frame(width: 24)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().background(Color.bhBorder)
                BillBodyView(bill: bill)
            }
        }
        .background(Color.bhSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isExpanded ? Color.bhBorder2 : Color.bhBorder, lineWidth: 1))
    }
}

struct BillBodyView: View {
    @EnvironmentObject var vm: AppViewModel
    @Binding var bill: Bill
    @State private var showRemoveConfirm = false

    init(bill: Bill) {
        // We need a binding so we find the index at render time
        self._bill = .constant(bill)
    }

    private var billIndex: Int? {
        vm.state.bills.firstIndex(where: { $0.id == bill.id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Split type toggle
            HStack(spacing: 8) {
                Text("Split Type")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.bhMuted)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(SplitType.allCases, id: \.self) { type in
                        Button(type.displayName) {
                            guard let idx = billIndex else { return }
                            vm.state.bills[idx].splitType = type
                            vm.save()
                        }
                        .font(.system(size: 11, design: .monospaced))
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
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Total bill input — used by pct bills (each line % × total) and
            // fixed bills (remainder line = total − sum of other lines)
            HStack {
                Text("Total Bill")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.bhMuted)
                if bill.splitType == .fixed {
                    Text("Remainder → \(vm.state.people.first { $0.id == (bill.lines.first { $0.id == bill.remainderLineId }?.personId ?? "") }?.name ?? "—")")
                        .font(.system(size: 10, design: .monospaced))
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

            // Lines header
            HStack {
                Text("Person").bhSectionTitle().frame(width: 100, alignment: .leading)
                Spacer()
                if bill.splitType == .pct {
                    Text("%").bhSectionTitle().frame(width: 50, alignment: .trailing)
                    Text("Amount").bhSectionTitle().frame(width: 80, alignment: .trailing)
                } else {
                    Text("Amount").bhSectionTitle().frame(width: 80, alignment: .trailing)
                }
                Spacer().frame(width: 28)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Lines
            ForEach(bill.lines) { line in
                BillLineRowView(bill: bill, line: line)
                Divider().background(Color.bhBorder).padding(.horizontal, 16)
            }

            // Add line
            Button {
                vm.addLine(to: bill.id)
            } label: {
                Label("Add Person", systemImage: "plus")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.bhMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(Color.bhBorder).padding(.horizontal, 16)

            // Preserve toggle
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
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.bhText)
                    Text("Copy last month's amounts when switching months")
                        .font(.system(size: 10, design: .monospaced))
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
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

        }
        .confirmationDialog("Remove \"\(bill.name)\"?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove Bill", role: .destructive) {
                vm.removeBill(bill)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the bill and all its settings.")
        }
    }
}

struct BillLineRowView: View {
    @EnvironmentObject var vm: AppViewModel
    let bill: Bill
    let line: BillLine

    private var billIndex: Int? { vm.state.bills.firstIndex { $0.id == bill.id } }
    private var lineIndex: Int? { bill.lines.firstIndex { $0.id == line.id } }

    // The effective payer: coveredById if set, otherwise the line's own personId
    private var effectivePayer: String { line.coveredById ?? line.personId }

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
            HStack(spacing: 8) {
                // Person picker (who is responsible)
                Picker("", selection: Binding(
                    get: { line.personId },
                    set: { val in
                        guard let bi = billIndex, let li = lineIndex else { return }
                        vm.state.bills[bi].lines[li].personId = val
                        // If the new responsible person is the same as coveredById, clear coverage
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
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 100)

                Spacer()

                if bill.splitType == .pct {
                    // Pct input
                    TextField("0", value: Binding(
                        get: { line.value },
                        set: { val in
                            vm.setLinePct(billId: bill.id, lineId: line.id, value: val)
                            vm.saveMonthSnapshot()
                        }
                    ), format: .number.precision(.fractionLength(0...2)))
                    .font(.system(size: 12, design: .monospaced))
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
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.bhAmber)
                        .frame(width: 80, alignment: .trailing)
                } else {
                    if line.id == bill.remainderLineId {
                        Text(computedAmount.asCurrency)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
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

                // Remove
                Button {
                    vm.removeLine(billId: bill.id, lineId: line.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.bhMuted)
                        .frame(width: 24, height: 24)
                        .background(Color.bhSurface2)
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.bhBorder, lineWidth: 1))
                }
                .disabled(bill.lines.count <= 1)
                .opacity(bill.lines.count <= 1 ? 0.3 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 5)

            // Covered-by sub-row
            HStack(spacing: 6) {
                Text("Covered by")
                    .font(.system(size: 10, design: .monospaced))
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
                .font(.system(size: 10, design: .monospaced))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 9)
        }
    }
}

struct CurrencyInputField: View {
    @Binding var value: Double
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0.00", text: $text)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
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
