import SwiftUI
import Charts

// MARK: - Trends View Mode

/// Segmented control options for the Trends tab.
enum TrendsViewMode: String, CaseIterable {
    case perPerson = "Per Person"
    case byBill = "By Bill"
}

// MARK: - Trends View

/// Month-over-month spend tracking with line charts, donut charts,
/// stacked bar charts, and a historical log.
///
/// Supports two modes via a segmented picker: "Per Person" (how much
/// each household member owes over time) and "By Bill" (how each bill's
/// total changes over time). Defaults to showing the last 12 months
/// with an option to expand to all available data.
struct TrendsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var mode: TrendsViewMode = .perPerson
    @State private var showAllMonths = false

    /// All month keys from the monthly data store, sorted chronologically.
    var sortedMonthKeys: [String] {
        vm.monthly.keys.sorted()
    }

    /// The month keys to display — either all or the most recent 12.
    var displayedMonthKeys: [String] {
        let all = sortedMonthKeys
        guard !showAllMonths, all.count > 12 else { return all }
        return Array(all.suffix(12))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HexBGView().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("View", selection: $mode) {
                            ForEach(TrendsViewMode.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 4)

                        if sortedMonthKeys.count > 12 {
                            Button {
                                showAllMonths.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showAllMonths ? "clock.arrow.trianglehead.counterclockwise.rotate.90" : "calendar")
                                        .font(.caption2)
                                    Text(showAllMonths ? "Showing all \(sortedMonthKeys.count) months — show last 12" : "Showing last 12 months — show all \(sortedMonthKeys.count)")
                                        .font(.bhCaption)
                                }
                                .foregroundColor(.bhAmber)
                            }
                        }

                        if sortedMonthKeys.isEmpty {
                            EmptyStateView(
                                systemImage: "chart.line.uptrend.xyaxis",
                                title: "No historical data yet",
                                subtitle: "Enter amounts for multiple months to see spending trends over time."
                            )
                        } else {
                            switch mode {
                            case .perPerson:
                                PersonTrendsView(monthKeys: displayedMonthKeys)
                            case .byBill:
                                BillTrendsView(monthKeys: displayedMonthKeys)
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                }
                .refreshable { await vm.refresh() }
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Trends Locked View

/// Shown when Trends is gated behind the paywall.
struct TrendsLockedView: View {
    let onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.bhAmber.opacity(0.5))
                .accessibilityHidden(true)
            Text("Trends")
                .font(.bhViewTitle)
                .foregroundColor(.bhText)
            Text("Unlock BillHive to see month-over-month\nspending insights and analytics.")
                .font(.bhBodySecondary)
                .foregroundColor(.bhMuted)
                .multilineTextAlignment(.center)
            Button {
                onUnlock()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                    Text("Unlock")
                        .font(.bhBodySecondary.weight(.semibold))
                }
                .frame(width: 160)
            }
            .buttonStyle(BHPrimaryButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Per Person Trends

/// Displays person-centric trend charts: a line chart of spending over time,
/// a donut chart of the current month's bill distribution, and a historical log.
struct PersonTrendsView: View {
    @EnvironmentObject var vm: AppViewModel
    let monthKeys: [String]

    /// A single data point for the per-person line chart.
    struct DataPoint: Identifiable {
        let id = UUID()
        let month: String
        let label: String
        let personId: String
        let personName: String
        let amount: Double
        let color: Color
    }

    /// Builds chart data by iterating every displayed month and computing
    /// per-person totals (the primary user's outlay + each other person's owed amount).
    var chartData: [DataPoint] {
        var points: [DataPoint] = []
        let nonMe = vm.state.people.filter { $0.id != "me" }

        for key in monthKeys {
            guard let md = vm.monthly[key] else { continue }
            let label = String(key.prefix(7))

            // Compute "me" total — use cached value or recompute from splits
            var myTotal = md._myTotal ?? 0
            if myTotal == 0 {
                for bill in vm.state.bills {
                    let billSplit = computeSplit(bill: bill, md: md)
                    myTotal += billSplit["me"] ?? 0
                }
            }
            points.append(DataPoint(month: key, label: label, personId: "me",
                                    personName: "Me", amount: myTotal, color: .bhAmber))

            for person in nonMe {
                let owes = md._owes?[person.id] ?? 0
                points.append(DataPoint(month: key, label: label, personId: person.id,
                                        personName: person.name, amount: owes,
                                        color: Color(hex: person.color) ?? .bhBlue))
            }
        }
        return points
    }

    /// Current month's per-bill totals for the donut chart.
    var currentMonthBillData: [(name: String, amount: Double, color: Color)] {
        vm.state.bills.compactMap { bill in
            let total = vm.monthly[vm.monthKey]?.totals[bill.id] ?? 0
            guard total > 0 else { return nil }
            return (name: bill.name, amount: total, color: Color(hex: bill.color) ?? .bhAmber)
        }
    }

    /// Computes the per-person split for a single bill using a specific month's data.
    ///
    /// Mirrors the logic in `AppViewModel.computeBillSplit`, but operates on
    /// an arbitrary `MonthData` instead of the current month.
    func computeSplit(bill: Bill, md: MonthData) -> [String: Double] {
        var result: [String: Double] = [:]
        for line in bill.lines {
            let amount: Double
            if bill.splitType == .pct {
                let total = md.totals[bill.id] ?? 0
                amount = total * line.value / 100.0
            } else {
                amount = md.amounts[bill.id]?[line.id] ?? 0
            }
            let payer = line.coveredById ?? line.personId
            result[payer, default: 0] += amount
        }
        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            // MARK: Line Chart

            VStack(alignment: .leading, spacing: 8) {
                Text("Total Bills Over Time")
                    .bhSectionTitle()
                    .padding(.bottom, 4)

                Chart(chartData) { point in
                    LineMark(
                        x: .value("Month", point.label),
                        y: .value("Amount", point.amount)
                    )
                    .foregroundStyle(by: .value("Person", point.personName))
                    .symbol(Circle().strokeBorder(lineWidth: 2))
                }
                .chartForegroundStyleScale(
                    domain: (["Me"] + vm.state.people.filter { $0.id != "me" }.map { $0.name }),
                    range: ([Color.bhAmber] + vm.state.people.filter { $0.id != "me" }.map { Color(hex: $0.color) ?? .bhBlue })
                )
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Color.bhBorder)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCurrency).font(.bhCaption).foregroundStyle(Color.bhMuted)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(String.self) {
                                Text(v).font(.bhCaption).foregroundStyle(Color.bhMuted)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
            .padding(16)
            .bhCard()

            // MARK: Donut Chart

            VStack(alignment: .leading, spacing: 8) {
                Text("This Month — By Bill")
                    .bhSectionTitle()

                if currentMonthBillData.isEmpty {
                    Text("No data this month")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    DonutChartView(items: currentMonthBillData)
                        .frame(height: 180)
                        .accessibilityHidden(true)

                    ForEach(currentMonthBillData, id: \.name) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 6, height: 6)
                            Text(item.name).font(.bhCaption).foregroundColor(.bhMuted)
                            Spacer()
                            Text(item.amount.asCurrency).font(.bhCaption.weight(.semibold)).foregroundColor(.bhText)
                        }
                    }
                }
            }
            .padding(16)
            .bhCard()

            // MARK: Historical Log

            VStack(alignment: .leading, spacing: 8) {
                Text("Historical Log")
                    .bhSectionTitle()

                ForEach(monthKeys.reversed(), id: \.self) { key in
                    if let md = vm.monthly[key] {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MonthKey.label(key))
                                .font(.bhCaption.weight(.semibold))
                                .foregroundColor(.bhText)

                            let owesMap = md._owes ?? [:]
                            ForEach(vm.state.people.filter { $0.id != "me" }) { person in
                                let amt = owesMap[person.id] ?? 0
                                HStack {
                                    Text(person.name).font(.bhCaption).foregroundColor(.bhMuted)
                                    Spacer()
                                    Text(amt.asCurrency).font(.bhCaption).foregroundColor(.bhText)
                                }
                            }
                        }
                        .padding(.bottom, 6)
                        Divider().background(Color.bhBorder)
                    }
                }
            }
            .padding(16)
            .bhCard()
        }
    }
}

// MARK: - Donut Chart

/// An iOS 16-compatible donut (ring) chart built with Canvas-free `Shape` segments.
///
/// Each segment is a `DonutSegment` with a small gap between slices for visual clarity.
struct DonutChartView: View {
    let items: [(name: String, amount: Double, color: Color)]

    /// Sum of all item amounts.
    private var total: Double { items.reduce(0) { $0 + $1.amount } }

    /// Pre-computed arc segments with start/end angles and fill color.
    private var segments: [(start: Angle, end: Angle, color: Color)] {
        var result: [(start: Angle, end: Angle, color: Color)] = []
        var current: Double = -90
        for item in items {
            let fraction = total > 0 ? item.amount / total : 0
            let sweep = fraction * 360
            let gap = 2.0
            result.append((
                start: Angle(degrees: current),
                end:   Angle(degrees: current + max(0, sweep - gap)),
                color: item.color
            ))
            current += sweep
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let outer = size / 2
            let inner = size * 0.30
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    DonutSegment(
                        startAngle: seg.start,
                        endAngle:   seg.end,
                        innerRadius: inner,
                        outerRadius: outer
                    )
                    .fill(seg.color)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Donut Segment Shape

/// A single arc segment of the donut chart, drawn as a closed path
/// between two concentric arcs.
struct DonutSegment: Shape {
    let startAngle: Angle
    let endAngle:   Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: outerRadius,
                    startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius,
                    startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - By Bill Trends

/// Displays bill-centric trend charts: a per-bill line chart, a stacked bar
/// chart of household totals, and a current-month summary table.
struct BillTrendsView: View {
    @EnvironmentObject var vm: AppViewModel
    let monthKeys: [String]

    /// A single data point for the per-bill line/bar charts.
    struct BillPoint: Identifiable {
        let id = UUID()
        let month: String
        let billName: String
        let amount: Double
        let color: Color
    }

    /// Builds chart data by iterating every displayed month and pulling
    /// each bill's total from the monthly data store.
    var chartData: [BillPoint] {
        var points: [BillPoint] = []
        for key in monthKeys {
            guard let md = vm.monthly[key] else { continue }
            let label = String(key.prefix(7))
            for bill in vm.state.bills {
                let total = md.totals[bill.id] ?? 0
                points.append(BillPoint(month: label, billName: bill.name,
                                        amount: total, color: Color(hex: bill.color) ?? .bhAmber))
            }
        }
        return points
    }

    var body: some View {
        VStack(spacing: 16) {
            // MARK: Per-Bill Line Chart

            VStack(alignment: .leading, spacing: 8) {
                Text("Per-Bill Totals Over Time")
                    .bhSectionTitle()

                Chart(chartData) { point in
                    LineMark(
                        x: .value("Month", point.month),
                        y: .value("Amount", point.amount)
                    )
                    .foregroundStyle(by: .value("Bill", point.billName))
                    .symbol(Circle().strokeBorder(lineWidth: 2))
                }
                .frame(height: 220)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Color.bhBorder)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCurrency).font(.bhCaption).foregroundStyle(Color.bhMuted)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .bhCard()

            // MARK: Stacked Bar Chart

            VStack(alignment: .leading, spacing: 8) {
                Text("Household Total by Month")
                    .bhSectionTitle()

                Chart(chartData) { point in
                    BarMark(
                        x: .value("Month", point.month),
                        y: .value("Amount", point.amount)
                    )
                    .foregroundStyle(by: .value("Bill", point.billName))
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Color.bhBorder)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.asCurrency).font(.bhCaption).foregroundStyle(Color.bhMuted)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .bhCard()

            // MARK: Current Month Summary

            VStack(alignment: .leading, spacing: 8) {
                Text("Bill Totals — This Month")
                    .bhSectionTitle()

                let md = vm.monthly[vm.monthKey]
                ForEach(vm.state.bills) { bill in
                    HStack {
                        Text("\(bill.icon) \(bill.name)")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                        Spacer()
                        Text((md?.totals[bill.id] ?? 0).asCurrency)
                            .font(.bhCaption.weight(.semibold))
                            .foregroundColor(.bhText)
                    }
                    .padding(.vertical, 2)
                }

                Divider().background(Color.bhBorder)

                let grandTotal = vm.state.bills.reduce(0.0) { $0 + (md?.totals[$1.id] ?? 0) }
                HStack {
                    Text("Total")
                        .font(.bhBodySecondary.weight(.semibold))
                        .foregroundColor(.bhText)
                    Spacer()
                    Text(grandTotal.asCurrency)
                        .font(.bhMoneySmall)
                        .foregroundColor(.bhAmber)
                }
            }
            .padding(16)
            .bhCard()
        }
    }
}
