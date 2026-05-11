import SwiftUI
import Charts

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
struct StatsRow: View {
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
