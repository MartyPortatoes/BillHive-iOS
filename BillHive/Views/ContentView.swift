import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Error banner — shown when load() fails
                if let err = vm.error {
                    ErrorBannerView(message: err) {
                        vm.error = nil
                        Task { await vm.load() }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                TabView(selection: $selectedTab) {
                    BillsView()
                        .tabItem {
                            Label("Bills", systemImage: "list.clipboard")
                        }
                        .tag(0)

                    SummaryView()
                        .tabItem {
                            Label("Summary", systemImage: "dollarsign.circle")
                        }
                        .tag(1)

                    SendReceiveView()
                        .tabItem {
                            Label("Send & Receive", systemImage: "arrow.up.arrow.down.circle")
                        }
                        .tag(2)

                    TrendsView()
                        .tabItem {
                            Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                        }
                        .tag(3)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag(4)
                }
                .accentColor(Color(hex: "#F5A800"))
            }

            // Toast overlay
            if let msg = vm.toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(999)
                    .padding(.bottom, 90)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.toastMessage)
        .animation(.easeInOut(duration: 0.25), value: vm.error)
        .preferredColorScheme(.dark)
    }
}

struct ErrorBannerView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.bhAmber)
                .font(.system(size: 13))
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.bhText)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: onRetry)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.bhAmber)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bhSurface)
        .overlay(Rectangle().fill(Color.bhBorder).frame(height: 1), alignment: .bottom)
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: "#F5A800") ?? .orange)
                .frame(width: 8, height: 8)
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color(hex: "#e4e5e8") ?? .white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#1c1e22") ?? Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "#34373d") ?? Color(.separator), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

// MARK: - Shared Design Tokens

extension Color {
    static let bhBackground = Color(hex: "#0c0d0f") ?? Color(.systemBackground)
    static let bhSurface = Color(hex: "#141518") ?? Color(.secondarySystemBackground)
    static let bhSurface2 = Color(hex: "#1c1e22") ?? Color(.tertiarySystemBackground)
    static let bhSurface3 = Color(hex: "#242629") ?? Color(.systemGray5)
    static let bhBorder = Color(hex: "#2a2c31") ?? Color(.separator)
    static let bhBorder2 = Color(hex: "#34373d") ?? Color(.separator)
    static let bhText = Color(hex: "#e4e5e8") ?? .primary
    static let bhMuted = Color(hex: "#767880") ?? .secondary
    static let bhMuted2 = Color(hex: "#4a4c52") ?? Color(.systemGray3)
    static let bhAmber = Color(hex: "#F5A800") ?? .orange
    static let bhBlue = Color(hex: "#5bc4f5") ?? .blue
    static let bhRed = Color(hex: "#ef5350") ?? .red
}

extension View {
    func bhCard() -> some View {
        self
            .background(Color.bhSurface)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.bhBorder, lineWidth: 1))
    }

    func bhSectionTitle() -> some View {
        self
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundColor(.bhMuted)
    }
}

// MARK: - Money Formatting

extension Double {
    var asCurrency: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = "$"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: self)) ?? "$\(String(format: "%.2f", self))"
    }
}
