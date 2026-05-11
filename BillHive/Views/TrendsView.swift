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

// Per-person trends are defined in PersonTrendsView.swift
// By-bill trends, donut chart, and shared chart components are defined in BillTrendsView.swift
