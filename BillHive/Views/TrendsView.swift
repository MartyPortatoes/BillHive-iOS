import SwiftUI
import Charts

enum TrendsViewMode: String, CaseIterable {
    case perPerson = "Per Person"
    case byBill = "By Bill"
}

struct TrendsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var mode: TrendsViewMode = .perPerson
    @State private var showAllMonths = false

    var sortedMonthKeys: [String] {
        vm.monthly.keys.sorted()
    }

    var displayedMonthKeys: [String] {
        let all = sortedMonthKeys
        guard !showAllMonths, all.count > 12 else { return all }
        return Array(all.suffix(12))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bhBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Trends")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(.bhText)
                                Text("Month-over-month spend tracking.")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.bhMuted)
                            }

                            Spacer()

                            Picker("View", selection: $mode) {
                                ForEach(TrendsViewMode.allCases, id: \.self) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        .padding(.top, 16)

                        if sortedMonthKeys.count > 12 {
                            Button {
                                showAllMonths.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showAllMonths ? "clock.arrow.trianglehead.counterclockwise.rotate.90" : "calendar")
                                        .font(.system(size: 10))
                                    Text(showAllMonths ? "Showing all \(sortedMonthKeys.count) months — show last 12" : "Showing last 12 months — show all \(sortedMonthKeys.count)")
                                        .font(.system(size: 10, design: .monospaced))
                                }
                                .foregroundColor(.bhAmber)
                            }
                        }

                        if sortedMonthKeys.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 32))
                                    .foregroundColor(.bhMuted)
                                Text("No historical data yet.\nEnter amounts for multiple months to see trends.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.bhMuted)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
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
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Per Person View

struct PersonTrendsView: View {
    @EnvironmentObject var vm: AppViewModel
    let monthKeys: [String]

    struct DataPoint: Identifiable {
        let id = UUID()
        let month: String
        let label: String
        let personId: String
        let personName: String
        let amount: Double
        let color: Color
    }

    var chartData: [DataPoint] {
        var points: [DataPoint] = []
        let nonMe = vm.state.people.filter { $0.id != "me" }

        for key in monthKeys {
            guard let md = vm.monthly[key] else { continue }
            let label = String(key.prefix(7))

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

    var currentMonthBillData: [(name: String, amount: Double, color: Color)] {
        vm.state.bills.compactMap { bill in
            let total = vm.monthly[vm.monthKey]?.totals[bill.id] ?? 0
            guard total > 0 else { return nil }
            return (name: bill.name, amount: total, color: Color(hex: bill.color) ?? .bhAmber)
        }
    }

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
            // Line chart — full width
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
                                Text(v.asCurrency).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.bhMuted)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(String.self) {
                                Text(v).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.bhMuted)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
            .padding(16)
            .bhCard()

            // This Month — By Bill donut — full width
            VStack(alignment: .leading, spacing: 8) {
                Text("This Month — By Bill")
                    .bhSectionTitle()

                if currentMonthBillData.isEmpty {
                    Text("No data this month")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.bhMuted2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    DonutChartView(items: currentMonthBillData)
                        .frame(height: 180)

                    ForEach(currentMonthBillData, id: \.name) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 6, height: 6)
                            Text(item.name).font(.system(size: 10, design: .monospaced)).foregroundColor(.bhMuted)
                            Spacer()
                            Text(item.amount.asCurrency).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.bhText)
                        }
                    }
                }
            }
            .padding(16)
            .bhCard()

            // Historical Log — full width
            VStack(alignment: .leading, spacing: 8) {
                Text("Historical Log")
                    .bhSectionTitle()

                ForEach(monthKeys.reversed(), id: \.self) { key in
                    if let md = vm.monthly[key] {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MonthKey.label(key))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.bhText)

                            let owesMap = md._owes ?? [:]
                            ForEach(vm.state.people.filter { $0.id != "me" }) { person in
                                let amt = owesMap[person.id] ?? 0
                                HStack {
                                    Text(person.name).font(.system(size: 9, design: .monospaced)).foregroundColor(.bhMuted)
                                    Spacer()
                                    Text(amt.asCurrency).font(.system(size: 9, design: .monospaced)).foregroundColor(.bhText)
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

// MARK: - iOS 16-compatible Donut Chart

struct DonutChartView: View {
    let items: [(name: String, amount: Double, color: Color)]

    private var total: Double { items.reduce(0) { $0 + $1.amount } }

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

// MARK: - By Bill View

struct BillTrendsView: View {
    @EnvironmentObject var vm: AppViewModel
    let monthKeys: [String]

    struct BillPoint: Identifiable {
        let id = UUID()
        let month: String
        let billName: String
        let amount: Double
        let color: Color
    }

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
            // Per-bill line chart — full width
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
                                Text(v.asCurrency).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.bhMuted)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .bhCard()

            // Stacked bar — full width
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
                                Text(v.asCurrency).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.bhMuted)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .bhCard()

            // Bill Totals this month — full width
            VStack(alignment: .leading, spacing: 8) {
                Text("Bill Totals — This Month")
                    .bhSectionTitle()

                let md = vm.monthly[vm.monthKey]
                ForEach(vm.state.bills) { bill in
                    HStack {
                        Text("\(bill.icon) \(bill.name)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.bhMuted)
                        Spacer()
                        Text((md?.totals[bill.id] ?? 0).asCurrency)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.bhText)
                    }
                    .padding(.vertical, 2)
                }

                Divider().background(Color.bhBorder)

                let grandTotal = vm.state.bills.reduce(0.0) { $0 + (md?.totals[$1.id] ?? 0) }
                HStack {
                    Text("Total")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.bhText)
                    Spacer()
                    Text(grandTotal.asCurrency)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.bhAmber)
                }
            }
            .padding(16)
            .bhCard()
        }
    }
}
