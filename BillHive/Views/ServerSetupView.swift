import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject var vm: AppViewModel
    @AppStorage("serverURL") private var serverURL: String = ""
    @State private var inputURL = ""
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var testSuccess = false

    var body: some View {
        ZStack {
            HexBGView().ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    HexLogoMark(size: 64)
                    Text("BillHive")
                        .font(.system(size: 28, weight: .black, design: .default))
                        .foregroundColor(.bhText)
                    Text("household manager")
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundColor(.bhMuted)
                }

                // Setup card
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connect to your BillHive server")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.bhText)

                    Text("Enter the URL of your self-hosted BillHive instance.")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.bhMuted)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server URL")
                            .bhSectionTitle()

                        TextField("http://192.168.1.100:8080", text: $inputURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.bhText)
                            .padding(10)
                            .background(Color.bhSurface2)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }

                    if let result = testResult {
                        HStack(spacing: 6) {
                            Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testSuccess ? .bhAmber : .bhRed)
                            Text(result)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(testSuccess ? .bhAmber : .bhRed)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack {
                                if isTesting {
                                    ProgressView().tint(.bhText).scaleEffect(0.7)
                                }
                                Text(isTesting ? "Testing..." : "Test Connection")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BHSecondaryButtonStyle())
                        .disabled(inputURL.isEmpty || isTesting)

                        Button {
                            saveAndConnect()
                        } label: {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BHPrimaryButtonStyle())
                        .disabled(inputURL.isEmpty || !testSuccess)
                    }
                }
                .padding(20)
                .bhCard()
                .padding(.horizontal, 24)

                Spacer()

                Text("Self-hosted · Your data stays on your server")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.bhMuted2)
            }
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let original = APIClient.shared.serverURL
        APIClient.shared.serverURL = inputURL
        do {
            let ok = try await APIClient.shared.health()
            testSuccess = ok
            testResult = ok ? "Connected successfully!" : "Server responded but health check failed"
        } catch {
            testSuccess = false
            testResult = error.localizedDescription
            APIClient.shared.serverURL = original
        }
        isTesting = false
    }

    private func saveAndConnect() {
        serverURL = inputURL
        APIClient.shared.serverURL = inputURL
    }
}

struct HexLogoMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            HexShape()
                .fill(Color.bhAmber)
                .frame(width: size, height: size * CGFloat(3).squareRoot() / 2)
            // Bill icon
            VStack(spacing: size * 0.06) {
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.45, height: size * 0.09)
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.6, height: size * 0.09)
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: "#0c0d0f") ?? .black)
                    .frame(width: size * 0.35, height: size * 0.09)
            }
        }
    }
}

struct HexShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let points: [CGPoint] = [
            CGPoint(x: w * 0.25, y: 0),
            CGPoint(x: w * 0.75, y: 0),
            CGPoint(x: w, y: h * 0.5),
            CGPoint(x: w * 0.75, y: h),
            CGPoint(x: w * 0.25, y: h),
            CGPoint(x: 0, y: h * 0.5)
        ]
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Button Styles

struct BHPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(hex: "#0c0d0f"))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(isEnabled ? Color.bhAmber : Color.bhAmber.opacity(0.4))
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BHSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.bhText)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.bhSurface2)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhBorder, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct BHDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.bhRed)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Color.bhSurface2)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.bhRed, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
