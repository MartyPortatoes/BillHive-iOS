import SwiftUI

// MARK: - Paywall View

/// Full-screen paywall presented when a user hits a gated feature.
///
/// Shows the app branding, feature highlights, price, purchase button,
/// and a restore link. Adapts messaging based on whether the trial
/// has expired vs never started.
struct PaywallView: View {
    @ObservedObject var purchaseManager = PurchaseManager.shared
    @Environment(\.dismiss) private var dismiss

    /// Optional context string shown at the top (e.g. "Unlock Trends").
    var featureContext: String? = nil

    var body: some View {
        ZStack {
            Color.bhBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // MARK: Header

                    VStack(spacing: 12) {
                        Image(systemName: "hexagon.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.bhAmber)
                            .padding(.top, 40)
                            .accessibilityHidden(true)

                        Text("BillHive")
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(.bhText)

                        if let context = featureContext {
                            Text(context)
                                .font(.bhBodySecondary)
                                .foregroundColor(.bhMuted)
                        }

                        if purchaseManager.trialDaysRemaining == 0 && !purchaseManager.isPurchased {
                            Text("Your free trial has ended")
                                .font(.bhBodySecondary.weight(.medium))
                                .foregroundColor(.bhRed)
                                .padding(.top, 4)
                        }
                    }

                    // MARK: Feature List

                    VStack(alignment: .leading, spacing: 14) {
                        FeatureRow(icon: "list.clipboard.fill", title: "Unlimited Bills", description: "Track as many bills as you need")
                        FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Trends & Analytics", description: "Month-over-month spending insights")
                        FeatureRow(icon: "envelope.fill", title: "Email Summaries", description: "Send bill breakdowns to your household")
                        FeatureRow(icon: "icloud.fill", title: "iCloud Sync", description: "Access your data across all devices")
                        FeatureRow(icon: "lock.open.fill", title: "One-Time Purchase", description: "Pay once, yours forever — no subscription")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .background(Color.bhSurface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.bhBorder, lineWidth: 1))
                    .padding(.horizontal, 20)

                    // MARK: Price + Purchase

                    VStack(spacing: 12) {
                        Button {
                            Task { await purchaseManager.purchase() }
                        } label: {
                            HStack(spacing: 8) {
                                if purchaseManager.isPurchasing {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text("Unlock BillHive — \(purchaseManager.priceText)")
                                        .font(.bhBody)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(BHPrimaryButtonStyle())
                        .disabled(purchaseManager.isPurchasing || purchaseManager.product == nil)
                        .padding(.horizontal, 20)

                        Button {
                            Task { await purchaseManager.restore() }
                        } label: {
                            Text("Restore Previous Purchase")
                                .font(.bhBodySecondary)
                                .foregroundColor(.bhMuted)
                        }

                        if let error = purchaseManager.errorMessage {
                            Text(error)
                                .font(.bhCaption)
                                .foregroundColor(.bhRed)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }

                    // MARK: Dismiss (if trial still active)

                    if purchaseManager.isTrialActive {
                        Button {
                            dismiss()
                        } label: {
                            Text("Continue with trial (\(purchaseManager.trialDaysRemaining) days left)")
                                .font(.bhBodySecondary)
                                .foregroundColor(.bhMuted)
                        }
                        .padding(.bottom, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .bhColorScheme()
        .interactiveDismissDisabled(!purchaseManager.isUnlocked)
        .onChange(of: purchaseManager.isPurchased) { purchased in
            if purchased { dismiss() }
        }
    }
}

// MARK: - Feature Row

/// A single feature highlight row in the paywall.
private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.bhAmber)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bhBodySecondary.weight(.semibold))
                    .foregroundColor(.bhText)
                Text(description)
                    .font(.bhCaption)
                    .foregroundColor(.bhMuted)
            }
        }
    }
}
