import SwiftUI

// MARK: - Onboarding View

/// First-launch carousel that introduces the app's core features through
/// stylized mockups (not screenshots, not overlays). Independent of the
/// actual UI, so it works identically on iPhone, iPad, all screen sizes,
/// and survives any future changes to the in-app layout.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private static let totalPages = 6
    /// Constrains content width on iPad so the carousel doesn't stretch.
    private let maxContentWidth: CGFloat = 520

    /// True when running on an iPad — switches the menu mock from a bottom
    /// tab bar to a sidebar, matching how SwiftUI's TabView actually renders
    /// on iPadOS.
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        ZStack {
            // Brand background
            Color.bhBackground.ignoresSafeArea()
            HexBGView()
                .opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button — hidden on the last page
                HStack {
                    Spacer()
                    if currentPage < OnboardingView.totalPages - 1 {
                        Button("Skip") { finish() }
                            .font(.bhBody)
                            .foregroundColor(.bhMuted)
                    } else {
                        // Reserve space so layout doesn't shift on last page
                        Text(" ").font(.bhBody)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(height: 40)

                // Pages — TabView in page style for free swipe gestures
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    billsPage.tag(1)
                    householdPage.tag(2)
                    summaryPage.tag(3)
                    payCollectPage.tag(4)
                    donePage.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .indexViewStyle(.page(backgroundDisplayMode: .never))

                // Bottom controls — custom dots + primary action
                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(0..<OnboardingView.totalPages, id: \.self) { i in
                            Circle()
                                .fill(i == currentPage ? Color.bhAmber : Color.bhMuted.opacity(0.35))
                                .frame(width: 8, height: 8)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }

                    Button {
                        if currentPage == OnboardingView.totalPages - 1 {
                            finish()
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        }
                    } label: {
                        Text(currentPage == OnboardingView.totalPages - 1 ? "Get Started" : "Next")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BHPrimaryButtonStyle())
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal, 40)
                }
                .padding(.bottom, 32)
            }
        }
    }

    private func finish() {
        hasCompletedOnboarding = true
    }

    // MARK: - Page Frame

    /// Standard page wrapper: vertically centered content, capped width
    /// for iPad, consistent vertical rhythm.
    /// - On iPhone: mockup → title → subtitle → menu mock (bottom tab bar)
    /// - On iPad:   menu mock (top pill) → mockup → title → subtitle
    @ViewBuilder
    private func pageFrame<Mockup: View>(
        selectedTab: Int,
        connectorStyle: ConnectorStyle = .gentleArc,
        @ViewBuilder mockup: () -> Mockup,
        title: String,
        subtitle: String
    ) -> some View {
        if isIPad {
            VStack(spacing: 0) {
                MenuMock(selectedTab: selectedTab, isIPad: true)
                    .padding(.top, 12)

                Spacer(minLength: 24)

                mockup()
                    .frame(maxWidth: maxContentWidth)

                Spacer().frame(height: 32)
                titleText(title)
                subtitleText(subtitle)

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 32)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 18)
                mockup()
                    .frame(maxWidth: maxContentWidth)
                    .padding(.horizontal, 32)
                Spacer().frame(height: 24)
                titleText(title)
                    .padding(.horizontal, 32)
                subtitleText(subtitle)
                    .padding(.bottom, 12)
                TabConnector(tabIndex: selectedTab, style: connectorStyle)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                MenuMock(selectedTab: selectedTab, isIPad: false)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private func titleText(_ s: String) -> some View {
        Text(s)
            .font(.title.weight(.heavy))
            .foregroundColor(.bhText)
            .multilineTextAlignment(.center)
    }

    private func subtitleText(_ s: String) -> some View {
        Text(s)
            .font(.bhBodySecondary)
            .foregroundColor(.bhMuted)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
            .padding(.horizontal, 40)
            .frame(maxWidth: maxContentWidth)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            TriHexLogoMark(size: 96)
                .padding(.bottom, 32)
            Text("Welcome to BillHive")
                .font(.largeTitle.weight(.black))
                .foregroundColor(.bhText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Split household bills with the people you live with — simply, fairly, and without the spreadsheet.")
                .font(.bhBody)
                .foregroundColor(.bhMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 40)
                .frame(maxWidth: maxContentWidth)
            Spacer()
            Spacer()
        }
    }

    private var billsPage: some View {
        pageFrame(
            selectedTab: 0,
            connectorStyle: .swoopLeft,
            mockup: {
                VStack(spacing: 10) {
                    BillMockRow(icon: "house.fill", name: "Rent", amount: "$1,500")
                    BillMockRow(icon: "bolt.fill", name: "Electric", amount: "$120")
                    BillMockRow(icon: "wifi", name: "Internet", amount: "$80")
                }
            },
            title: "Track Every Bill",
            subtitle: "Add your recurring bills in one place — rent, utilities, groceries, anything you split."
        )
    }

    private var householdPage: some View {
        pageFrame(
            selectedTab: 4,
            connectorStyle: .loop,
            mockup: {
                HStack(spacing: 18) {
                    PersonMockAvatar(label: "You",    color: .bhAmber)
                    PersonMockAvatar(label: "Alex",   color: Color(hex: "#5bc4f5") ?? .blue)
                    PersonMockAvatar(label: "Maya",   color: Color(hex: "#a48bf2") ?? .purple)
                    PersonMockAvatar(label: "Jordan", color: Color(hex: "#65c987") ?? .green)
                }
            },
            title: "Add Your Household",
            subtitle: "Open Settings to add roommates, partners, or anyone who chips in."
        )
    }

    private var summaryPage: some View {
        pageFrame(
            selectedTab: 1,
            connectorStyle: .wave,
            mockup: { SummaryMockCard() },
            title: "See Who Owes What",
            subtitle: "BillHive does the math — a clear monthly breakdown of who pays whom."
        )
    }

    private var payCollectPage: some View {
        pageFrame(
            selectedTab: 2,
            connectorStyle: .wideArc,
            mockup: {
                VStack(spacing: 10) {
                    CollectMockRow(person: "Megan",  method: "Zelle",    amount: "$224.50", accentHex: "#5bc4f5")
                    CollectMockRow(person: "Alex",   method: "Venmo",    amount: "$118.20", accentHex: "#ff7a3a")
                    CollectMockRow(person: "Jordan", method: "Cash App", amount: "$76.85",  accentHex: "#65c987")
                }
            },
            title: "Collect What You're Owed",
            subtitle: "Notify housemates what they owe and request payment via Zelle, Venmo, or Cash App."
        )
    }

    private var donePage: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.bhAmber.opacity(0.15))
                    .frame(width: 128, height: 128)
                Circle()
                    .stroke(Color.bhAmber, lineWidth: 2)
                    .frame(width: 128, height: 128)
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .heavy))
                    .foregroundColor(.bhAmber)
            }
            .padding(.bottom, 32)
            Text("You're All Set!")
                .font(.largeTitle.weight(.black))
                .foregroundColor(.bhText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Open Settings → Household to add the people you split with, then create your first bill.")
                .font(.bhBody)
                .foregroundColor(.bhMuted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 40)
                .frame(maxWidth: maxContentWidth)
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Mockup Components

/// A simplified bill row reminiscent of the actual BillCardView, used in
/// the Bills onboarding page. Pure mockup — not wired to any real data.
private struct BillMockRow: View {
    let icon: String
    let name: String
    let amount: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.bhAmber.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.bhAmber)
            }
            Text(name)
                .font(.bhBody)
                .foregroundColor(.bhText)
            Spacer()
            Text(amount)
                .font(.bhBody.monospacedDigit().weight(.semibold))
                .foregroundColor(.bhText)
        }
        .padding(14)
        .background(Color.bhSurface2)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.bhBorder, lineWidth: 1)
        )
    }
}

/// A circular avatar with a label below it. Used to represent household
/// members in the Household onboarding page.
private struct PersonMockAvatar: View {
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                Circle()
                    .stroke(color, lineWidth: 2)
                Text(String(label.prefix(2)).uppercased())
                    .font(.bhBody.weight(.bold))
                    .foregroundColor(color)
            }
            .frame(width: 56, height: 56)
            Text(label)
                .font(.bhBodySecondary)
                .foregroundColor(.bhMuted)
                .lineLimit(1)
        }
    }
}

/// A simplified summary breakdown card showing who owes what, used in
/// the Summary onboarding page.
private struct SummaryMockCard: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alex")
                        .font(.bhBody.weight(.semibold))
                        .foregroundColor(.bhText)
                    Text("owes you for May")
                        .font(.bhBodySecondary)
                        .foregroundColor(.bhMuted)
                }
                Spacer()
                Text("$566.67")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundColor(.bhAmber)
            }

            Rectangle()
                .fill(Color.bhBorder)
                .frame(height: 1)

            VStack(spacing: 8) {
                SummaryMockLine(label: "Rent",     amount: "$500.00")
                SummaryMockLine(label: "Electric", amount: "$40.00")
                SummaryMockLine(label: "Internet", amount: "$26.67")
            }
        }
        .padding(16)
        .background(Color.bhSurface2)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bhBorder, lineWidth: 1)
        )
    }
}

private struct SummaryMockLine: View {
    let label: String
    let amount: String

    var body: some View {
        HStack {
            Text(label)
                .font(.bhBodySecondary)
                .foregroundColor(.bhMuted)
            Spacer()
            Text(amount)
                .font(.bhBodySecondary.monospacedDigit())
                .foregroundColor(.bhText)
        }
    }
}

/// A simplified "owed amount" row showing a person, their preferred payment
/// method, and the outstanding balance with a colored method tag.
/// Used in the Pay & Collect onboarding page to mirror the actual app's
/// Collect section, which lets the user request payment via Zelle, Venmo,
/// or Cash App.
private struct CollectMockRow: View {
    let person: String
    let method: String
    let amount: String
    let accentHex: String

    var body: some View {
        let accent = Color(hex: accentHex) ?? .gray
        return HStack(spacing: 12) {
            // Person dot (matches assigned person color in the real app)
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(person)
                    .font(.bhBody.weight(.semibold))
                    .foregroundColor(.bhText)
                Text(method)
                    .font(.bhBodySecondary)
                    .foregroundColor(.bhMuted)
            }

            Spacer()

            Text(amount)
                .font(.bhBody.weight(.semibold).monospacedDigit())
                .foregroundColor(accent)

            // Method pill — matches the colored tag used in the real Collect view
            Text(method)
                .font(.caption2.weight(.bold))
                .foregroundColor(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accent.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(accent.opacity(0.4), lineWidth: 1)
                )
        }
        .padding(14)
        .background(Color.bhSurface2)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.bhBorder, lineWidth: 1)
        )
    }
}

/// Stylized rendering of the app's navigation menu, with one item highlighted
/// to ground the onboarding step in the actual UI the user will see.
/// Renders as a horizontal bottom tab bar on iPhone, and as a vertical
/// sidebar on iPad — matching how SwiftUI's TabView actually presents itself.
private struct MenuMock: View {
    let selectedTab: Int
    let isIPad: Bool

    private static let tabs: [(icon: String, selectedIcon: String, label: String)] = [
        ("list.clipboard",              "list.clipboard.fill",              "Bills"),
        ("dollarsign.circle",           "dollarsign.circle.fill",           "Summary"),
        ("arrow.up.arrow.down.circle",  "arrow.up.arrow.down.circle.fill", "Pay & Collect"),
        ("chart.line.uptrend.xyaxis",   "chart.line.uptrend.xyaxis",       "Trends"),
        ("gearshape",                   "gearshape.fill",                   "Settings"),
    ]

    var body: some View {
        if isIPad {
            iPadPillBar
        } else {
            tabBar
        }
    }

    // MARK: iPhone — bottom tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<Self.tabs.count, id: \.self) { i in
                let tab = Self.tabs[i]
                let selected = selectedTab == i
                VStack(spacing: 2) {
                    Image(systemName: selected ? tab.selectedIcon : tab.icon)
                        .font(.title3)
                        .frame(height: 28)
                    Text(tab.label)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(selected ? .bhAmber : .bhMuted)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color.bhSurface2)
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.bhBorder, lineWidth: 1)
        )
    }

    // MARK: iPad — top pill bar

    /// On iPad, SwiftUI's TabView renders as a horizontal capsule at the top
    /// of the screen with text-only labels (no icons) and an amber pill behind
    /// the selected tab — that's what we mirror here.
    private var iPadPillBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.tabs.count, id: \.self) { i in
                let tab = Self.tabs[i]
                let selected = selectedTab == i
                Text(tab.label)
                    .font(.bhBody.weight(.semibold))
                    .foregroundColor(selected ? .bhAmber : .bhText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(selected ? Color.bhAmber.opacity(0.20) : Color.clear)
                    )
            }
        }
        .padding(4)
        .background(Color.bhSurface2)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.bhBorder, lineWidth: 1)
        )
    }
}

// MARK: - Connector Line + Arrow

private enum ConnectorStyle {
    case swoopLeft
    case loop
    case wave
    case wideArc
    case gentleArc
}

/// Draws a fun dotted line from the center-top (below the subtitle) down to
/// an arrow that points at the selected tab in the menu bar below.
private struct TabConnector: View {
    let tabIndex: Int
    let style: ConnectorStyle
    private let tabCount = 5
    private let arrowSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let tabWidth = w / CGFloat(tabCount)
            let targetX = tabWidth * CGFloat(tabIndex) + tabWidth / 2
            let startX = w / 2
            let endY = h - arrowSize

            connectorPath(
                from: CGPoint(x: startX, y: 0),
                to: CGPoint(x: targetX, y: endY),
                in: geo.size
            )
            .stroke(
                Color.bhAmber.opacity(0.5),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5])
            )

            Triangle()
                .fill(Color.bhAmber)
                .frame(width: arrowSize, height: arrowSize * 0.65)
                .position(x: targetX, y: h - arrowSize * 0.65 / 2)
        }
        .frame(minHeight: 60, maxHeight: .infinity)
    }

    private func connectorPath(from start: CGPoint, to end: CGPoint, in size: CGSize) -> Path {
        switch style {
        case .swoopLeft:
            return swoopLeftPath(from: start, to: end, in: size)
        case .loop:
            return loopPath(from: start, to: end, in: size)
        case .wave:
            return wavePath(from: start, to: end, in: size)
        case .wideArc:
            return wideArcPath(from: start, to: end, in: size)
        case .gentleArc:
            return gentleArcPath(from: start, to: end, in: size)
        }
    }

    // Gentle swoop curving out left then back to the target
    private func swoopLeftPath(from s: CGPoint, to e: CGPoint, in sz: CGSize) -> Path {
        return Path { p in
            p.move(to: s)
            p.addCurve(
                to: e,
                control1: CGPoint(x: s.x - sz.width * 0.35, y: s.y + (e.y - s.y) * 0.3),
                control2: CGPoint(x: e.x + sz.width * 0.15, y: e.y - (e.y - s.y) * 0.25)
            )
        }
    }

    // Line curves left, loops around itself, then lands on the far-right tab
    private func loopPath(from s: CGPoint, to e: CGPoint, in sz: CGSize) -> Path {
        let dy = e.y - s.y
        return Path { p in
            p.move(to: s)
            // First segment: curve out to the left
            let mid1 = CGPoint(x: s.x - sz.width * 0.15, y: s.y + dy * 0.35)
            p.addCurve(
                to: mid1,
                control1: CGPoint(x: s.x - sz.width * 0.25, y: s.y + dy * 0.05),
                control2: CGPoint(x: s.x - sz.width * 0.3, y: s.y + dy * 0.3)
            )
            // Loop: small clockwise circle
            let loopR: CGFloat = dy * 0.12
            let loopCenter = CGPoint(x: mid1.x + loopR, y: mid1.y)
            p.addArc(
                center: loopCenter,
                radius: loopR,
                startAngle: .degrees(180),
                endAngle: .degrees(540),
                clockwise: false
            )
            // Final segment: swoop from loop exit to target
            p.addCurve(
                to: e,
                control1: CGPoint(x: mid1.x + sz.width * 0.25, y: mid1.y + dy * 0.1),
                control2: CGPoint(x: e.x - sz.width * 0.05, y: e.y - dy * 0.2)
            )
        }
    }

    // Sine-wave wiggle from center down to the target
    private func wavePath(from s: CGPoint, to e: CGPoint, in sz: CGSize) -> Path {
        let dy = e.y - s.y
        let dx = e.x - s.x
        let segments = 3
        let segH = dy / CGFloat(segments)
        let amplitude = sz.width * 0.12

        return Path { p in
            p.move(to: s)
            for i in 0..<segments {
                let frac0 = CGFloat(i) / CGFloat(segments)
                let frac1 = CGFloat(i + 1) / CGFloat(segments)
                let y0 = s.y + dy * frac0
                let y1 = s.y + dy * frac1
                let x0 = s.x + dx * frac0
                let x1 = s.x + dx * frac1
                let dir: CGFloat = i.isMultiple(of: 2) ? 1 : -1
                p.addCurve(
                    to: CGPoint(x: x1, y: y1),
                    control1: CGPoint(x: x0 + amplitude * dir, y: y0 + segH * 0.33),
                    control2: CGPoint(x: x1 + amplitude * dir, y: y1 - segH * 0.33)
                )
            }
        }
    }

    // Wide sweeping arc that goes way out to one side
    private func wideArcPath(from s: CGPoint, to e: CGPoint, in sz: CGSize) -> Path {
        Path { p in
            p.move(to: s)
            p.addCurve(
                to: e,
                control1: CGPoint(x: s.x + sz.width * 0.4, y: s.y + (e.y - s.y) * 0.15),
                control2: CGPoint(x: e.x - sz.width * 0.3, y: e.y - (e.y - s.y) * 0.1)
            )
        }
    }

    // Simple gentle arc (default/fallback)
    private func gentleArcPath(from s: CGPoint, to e: CGPoint, in sz: CGSize) -> Path {
        Path { p in
            p.move(to: s)
            p.addQuadCurve(
                to: e,
                control: CGPoint(x: (s.x + e.x) / 2 + 30, y: (s.y + e.y) / 2)
            )
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
