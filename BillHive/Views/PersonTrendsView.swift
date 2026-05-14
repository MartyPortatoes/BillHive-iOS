import SwiftUI
import Charts

// MARK: - Per Person Trends

/// Displays person-centric trend charts: a line chart of spending over time,
/// a donut chart of the current month's bill distribution, and a historical log.
struct PersonTrendsView: View {
    @EnvironmentObject var vm: AppViewModel
    let monthKeys: [String]
    @State private var selectedPoint: DataPoint?
    @State private var expandedLogEntry: String?
    @State private var showHistoricalLog = false

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
                myTotal = vm.computeMyTotal(using: md)
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
                            .annotation(position: .overlay, alignment: .top) {
                                ChartAnnotationBubble(title: sel.personName, month: sel.label,
                                                      amount: sel.amount, color: sel.color)
                                    .padding(.top, 4)
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
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showHistoricalLog.toggle()
                    }
                } label: {
                    HStack {
                        Text("Historical Log")
                            .bhSectionTitle()
                        Spacer()
                        Image(systemName: showHistoricalLog ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.bhMuted)
                    }
                }

                if showHistoricalLog {
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
                                            let splits = vm.computeBillSplit(bill, using: md)
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
                                        let splits = vm.computeBillSplit(bill, using: md)
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
                } // end if showHistoricalLog
            }
            .padding(16)
            .bhCard()
        }
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

    @ViewBuilder
    var body: some View {
        let totals = myTotals
        if !totals.isEmpty {
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
        }
    }
}
