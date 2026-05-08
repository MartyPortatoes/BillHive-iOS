import SwiftUI
import Charts

// MARK: - Trends View Mode

/// Segmented control options for the Trends tab.
enum TrendsViewMode: String, CaseIterable {
    case perPerson = "Per Person"
    case byBill = "By Bill"
}

/// Date range filter for Trends charts.
enum TrendsRange: String, CaseIterable {
    case sixMonths = "6M"
    case twelveMonths = "12M"
    case twentyFourMonths = "24M"
    case all = "All"

    var monthCount: Int? {
        switch self {
        case .sixMonths: return 6
        case .twelveMonths: return 12
        case .twentyFourMonths: return 24
        case .all: return nil
        }
    }
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
    @State private var range: TrendsRange = .twelveMonths

    /// All month keys from the monthly data store, sorted chronologically.
    var sortedMonthKeys: [String] {
        vm.monthly.keys.sorted()
    }

    /// The month keys to display based on the selected range.
    var displayedMonthKeys: [String] {
        let all = sortedMonthKeys
        guard let limit = range.monthCount, all.count > limit else { return all }
        return Array(all.suffix(limit))
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

                        if sortedMonthKeys.count > 6 {
                            Picker("Range", selection: $range) {
                                ForEach(TrendsRange.allCases, id: \.self) { r in
                                    Text(r.rawValue).tag(r)
                                }
                            }
                            .pickerStyle(.segmented)
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
    @State private var selectedPoint: DataPoint?
    @State private var expandedLogEntry: String?

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

                Chart {
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Month", point.label),
                            y: .value("Amount", point.amount)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Person", point.personName))
                        .symbol(Circle().strokeBorder(lineWidth: 2))
                    }

                    if let sel = selectedPoint {
                        RuleMark(x: .value("Selected", sel.label))
                            .foregroundStyle(Color.bhMuted2)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .center) {
                                ChartAnnotationBubble(title: sel.personName, month: sel.label,
                                                      amount: sel.amount, color: sel.color)
                            }
                        PointMark(x: .value("Month", sel.label), y: .value("Amount", sel.amount))
                            .foregroundStyle(sel.color)
                            .symbolSize(100)
                    }
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
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        let origin = geo[proxy.plotAreaFrame].origin
                                        let x = drag.location.x - origin.x
                                        guard let month: String = proxy.value(atX: x) else { return }
                                        let candidates = chartData.filter { $0.label == month }
                                        guard !candidates.isEmpty else { return }
                                        let y = drag.location.y - origin.y
                                        selectedPoint = candidates.min(by: {
                                            let y0 = proxy.position(forY: $0.amount) ?? 0
                                            let y1 = proxy.position(forY: $1.amount) ?? 0
                                            return abs(y0 - y) < abs(y1 - y)
                                        })
                                    }
                            )
                            .onTapGesture { selectedPoint = nil }
                    }
                }
                .frame(height: 220)
            }
            .padding(16)
            .bhCard()

            // MARK: Summary Stats

            PersonSummaryStatsCard(chartData: chartData, monthKeys: monthKeys)

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
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedLogEntry = expandedLogEntry == key ? nil : key
                                }
                            } label: {
                                HStack {
                                    Text(MonthKey.label(key))
                                        .font(.bhCaption.weight(.semibold))
                                        .foregroundColor(.bhText)
                                    Spacer()
                                    Image(systemName: expandedLogEntry == key ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.bhMuted2)
                                }
                            }

                            let owesMap = md._owes ?? [:]
                            ForEach(vm.state.people.filter { $0.id != "me" }) { person in
                                let amt = owesMap[person.id] ?? 0
                                VStack(spacing: 0) {
                                    HStack {
                                        Circle().fill(Color(hex: person.color) ?? .bhBlue)
                                            .frame(width: 6, height: 6)
                                        Text(person.name).font(.bhCaption).foregroundColor(.bhMuted)
                                        Spacer()
                                        Text(amt.asCurrency).font(.bhCaption).foregroundColor(.bhText)
                                    }

                                    // Per-bill breakdown when expanded
                                    if expandedLogEntry == key {
                                        ForEach(vm.state.bills) { bill in
                                            let splits = computeSplit(bill: bill, md: md)
                                            let personAmt = splits[person.id] ?? 0
                                            if personAmt > 0 {
                                                HStack {
                                                    Text("  \(bill.icon) \(bill.name)")
                                                        .font(.bhCaption)
                                                        .foregroundColor(.bhMuted2)
                                                    Spacer()
                                                    Text(personAmt.asCurrency)
                                                        .font(.bhCaption)
                                                        .foregroundColor(.bhMuted)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Show "Me" total when expanded
                            if expandedLogEntry == key {
                                let myTotal = md._myTotal ?? 0
                                VStack(spacing: 0) {
                                    HStack {
                                        Circle().fill(Color.bhAmber).frame(width: 6, height: 6)
                                        Text("Me").font(.bhCaption).foregroundColor(.bhMuted)
                                        Spacer()
                                        Text(myTotal.asCurrency).font(.bhCaption).foregroundColor(.bhText)
                                    }
                                    ForEach(vm.state.bills) { bill in
                                        let splits = computeSplit(bill: bill, md: md)
                                        let myAmt = splits["me"] ?? 0
                                        if myAmt > 0 {
                                            HStack {
                                                Text("  \(bill.icon) \(bill.name)")
                                                    .font(.bhCaption)
                                                    .foregroundColor(.bhMuted2)
                                                Spacer()
                                                Text(myAmt.asCurrency)
                                                    .font(.bhCaption)
                                                    .foregroundColor(.bhMuted)
                                            }
                                        }
                                    }
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
    @State private var selectedBillPoint: BillPoint?
    @State private var selectedBarMonth: String?

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

                Chart {
                    ForEach(chartData) { point in
                        LineMark(
                            x: .value("Month", point.month),
                            y: .value("Amount", point.amount)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(by: .value("Bill", point.billName))
                        .symbol(Circle().strokeBorder(lineWidth: 2))
                    }

                    if let sel = selectedBillPoint {
                        RuleMark(x: .value("Selected", sel.month))
                            .foregroundStyle(Color.bhMuted2)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .center) {
                                ChartAnnotationBubble(title: sel.billName, month: sel.month,
                                                      amount: sel.amount, color: sel.color)
                            }
                        PointMark(x: .value("Month", sel.month), y: .value("Amount", sel.amount))
                            .foregroundStyle(sel.color)
                            .symbolSize(100)
                    }
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
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        let origin = geo[proxy.plotAreaFrame].origin
                                        let x = drag.location.x - origin.x
                                        guard let month: String = proxy.value(atX: x) else { return }
                                        let candidates = chartData.filter { $0.month == month }
                                        guard !candidates.isEmpty else { return }
                                        let y = drag.location.y - origin.y
                                        selectedBillPoint = candidates.min(by: {
                                            let y0 = proxy.position(forY: $0.amount) ?? 0
                                            let y1 = proxy.position(forY: $1.amount) ?? 0
                                            return abs(y0 - y) < abs(y1 - y)
                                        })
                                    }
                            )
                            .onTapGesture { selectedBillPoint = nil }
                    }
                }
            }
            .padding(16)
            .bhCard()

            // MARK: Stacked Bar Chart

            VStack(alignment: .leading, spacing: 8) {
                Text("Household Total by Month")
                    .bhSectionTitle()

                Chart {
                    ForEach(chartData) { point in
                        BarMark(
                            x: .value("Month", point.month),
                            y: .value("Amount", point.amount)
                        )
                        .foregroundStyle(by: .value("Bill", point.billName))
                        .opacity(selectedBarMonth == nil || selectedBarMonth == point.month ? 1 : 0.3)
                    }

                    if let sel = selectedBarMonth {
                        let total = chartData.filter { $0.month == sel }.reduce(0) { $0 + $1.amount }
                        RuleMark(x: .value("Selected", sel))
                            .foregroundStyle(Color.bhMuted2)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .center) {
                                ChartAnnotationBubble(title: "Total", month: sel,
                                                      amount: total, color: .bhAmber)
                            }
                    }
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
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        let origin = geo[proxy.plotAreaFrame].origin
                                        let x = drag.location.x - origin.x
                                        guard let month: String = proxy.value(atX: x) else { return }
                                        selectedBarMonth = month
                                    }
                            )
                            .onTapGesture { selectedBarMonth = nil }
                    }
                }
            }
            .padding(16)
            .bhCard()

            // MARK: Bill Summary Stats

            BillSummaryStatsCard(chartData: chartData, monthKeys: monthKeys)

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

// MARK: - Chart Annotation Bubble

/// Compact annotation popup shown when tapping a chart data point.
struct ChartAnnotationBubble: View {
    let title: String
    let month: String
    let amount: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(month)
                .font(.bhCaption)
                .foregroundColor(.bhMuted)
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.bhCaption.weight(.semibold))
                    .foregroundColor(.bhText)
            }
            Text(amount.asCurrency)
                .font(.bhBodySecondary.weight(.bold))
                .foregroundColor(.bhAmber)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.bhSurface2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.bhBorder, lineWidth: 1)
        )
    }
}

// MARK: - Person Summary Stats Card

/// Insights card for the Per Person mode: average monthly total for "Me",
/// highest/lowest months, and month-over-month change.
struct PersonSummaryStatsCard: View {
    let chartData: [PersonTrendsView.DataPoint]
    let monthKeys: [String]

    private var myTotals: [(month: String, amount: Double)] {
        monthKeys.compactMap { key in
            let label = String(key.prefix(7))
            guard let pt = chartData.first(where: { $0.label == label && $0.personId == "me" }) else { return nil }
            return (month: label, amount: pt.amount)
        }
    }

    var body: some View {
        let totals = myTotals
        guard !totals.isEmpty else { return AnyView(EmptyView()) }

        let amounts = totals.map(\.amount)
        let avg = amounts.reduce(0, +) / Double(amounts.count)
        let highest = totals.max(by: { $0.amount < $1.amount })
        let lowest = totals.min(by: { $0.amount < $1.amount })

        // Month-over-month change
        let momChange: Double? = {
            guard totals.count >= 2 else { return nil }
            let current = totals[totals.count - 1].amount
            let previous = totals[totals.count - 2].amount
            guard previous > 0 else { return nil }
            return ((current - previous) / previous) * 100
        }()

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Insights")
                    .bhSectionTitle()

                StatsRow(label: "Monthly Avg (You)", value: avg.asCurrency)

                if let h = highest {
                    StatsRow(label: "Highest Month", value: "\(h.amount.asCurrency)", detail: h.month)
                }
                if let l = lowest {
                    StatsRow(label: "Lowest Month", value: "\(l.amount.asCurrency)", detail: l.month)
                }
                if let change = momChange {
                    HStack {
                        Text("vs Last Month")
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption2)
                            Text(String(format: "%.1f%%", abs(change)))
                                .font(.bhCaption.weight(.semibold))
                        }
                        .foregroundColor(change > 0 ? .bhRed : (change < 0 ? Color(hex: "#4caf50") ?? .green : .bhMuted))
                    }
                }
            }
            .padding(16)
            .bhCard()
        )
    }
}

// MARK: - Bill Summary Stats Card

/// Insights card for the By Bill mode: average per bill across displayed months.
struct BillSummaryStatsCard: View {
    let chartData: [BillTrendsView.BillPoint]
    let monthKeys: [String]

    var body: some View {
        let billNames = Array(Set(chartData.map(\.billName))).sorted()
        guard !billNames.isEmpty, !monthKeys.isEmpty else { return AnyView(EmptyView()) }

        let monthCount = Double(monthKeys.count)

        // Compute average per bill
        let billAverages: [(name: String, avg: Double, color: Color)] = billNames.compactMap { name in
            let points = chartData.filter { $0.billName == name }
            guard !points.isEmpty else { return nil }
            let total = points.reduce(0) { $0 + $1.amount }
            let color = points.first?.color ?? .bhAmber
            return (name: name, avg: total / monthCount, color: color)
        }.sorted(by: { $0.avg > $1.avg })

        // Overall household average
        let householdTotal = chartData.reduce(0) { $0 + $1.amount }
        let householdAvg = householdTotal / monthCount

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("Averages (\(monthKeys.count) months)")
                    .bhSectionTitle()

                ForEach(billAverages, id: \.name) { bill in
                    HStack(spacing: 6) {
                        Circle().fill(bill.color).frame(width: 6, height: 6)
                        Text(bill.name)
                            .font(.bhCaption)
                            .foregroundColor(.bhMuted)
                        Spacer()
                        Text(bill.avg.asCurrency)
                            .font(.bhCaption.weight(.semibold))
                            .foregroundColor(.bhText)
                    }
                }

                Divider().background(Color.bhBorder)

                HStack {
                    Text("Household Avg")
                        .font(.bhBodySecondary.weight(.semibold))
                        .foregroundColor(.bhText)
                    Spacer()
                    Text(householdAvg.asCurrency)
                        .font(.bhMoneySmall)
                        .foregroundColor(.bhAmber)
                }
            }
            .padding(16)
            .bhCard()
        )
    }
}

// MARK: - Stats Row

/// A single row in a summary stats card: label on the left, value (+ optional detail) on the right.
private struct StatsRow: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.bhCaption)
                .foregroundColor(.bhMuted)
            Spacer()
            HStack(spacing: 4) {
                Text(value)
                    .font(.bhCaption.weight(.semibold))
                    .foregroundColor(.bhText)
                if let detail {
                    Text("(\(detail))")
                        .font(.bhCaption)
                        .foregroundColor(.bhMuted2)
                }
            }
        }
    }
}
