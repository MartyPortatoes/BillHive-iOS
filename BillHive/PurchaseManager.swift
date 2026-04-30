import Foundation
import StoreKit

// MARK: - Purchase Manager

/// Manages the app's in-app purchase and 14-day free trial.
///
/// Uses StoreKit 2 for a single non-consumable product ("full unlock").
/// Trial start date is stored in both UserDefaults and iCloud KV store
/// so it survives app reinstalls on the same Apple ID.
@MainActor
class PurchaseManager: ObservableObject {

    static let shared = PurchaseManager()

    // MARK: - Configuration

    /// The product identifier configured in App Store Connect.
    nonisolated static let productId = "com.billhive.app.unlock"

    /// Number of days for the free trial.
    static let trialDays = 14

    // MARK: - Published State

    /// Whether the user has full access (purchased OR within trial period).
    /// Defaults to `false` so the paywall holds during the cold-start window
    /// before `setup()` has computed the real entitlement state. `setup()`
    /// flips this to `true` for purchasers and active-trial users.
    @Published var isUnlocked: Bool = false
    /// Whether the user has purchased the IAP (distinct from trial).
    @Published var isPurchased: Bool = false
    /// Days remaining in the trial, or 0 if expired/purchased.
    @Published var trialDaysRemaining: Int = 0
    /// Whether the trial is currently active (not expired, not purchased).
    @Published var isTrialActive: Bool = false
    /// The StoreKit product, fetched on launch.
    @Published var product: Product? = nil
    /// Whether a purchase is currently in progress.
    @Published var isPurchasing: Bool = false
    /// Error message from the most recent failed operation.
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private var transactionListener: Task<Void, Never>? = nil

    private let trialStartKey = "billhive_trial_start"

    // MARK: - Init

    private init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Setup

    /// Call once on app launch to load product, check entitlements, and start trial clock.
    func setup() async {
        await fetchProduct()
        await checkEntitlements()
        ensureTrialStartDate()
        refreshUnlockState()
    }

    // MARK: - Product

    /// Fetches the IAP product from the App Store.
    private func fetchProduct() async {
        do {
            let products = try await Product.products(for: [Self.productId])
            product = products.first
        } catch {
            errorMessage = "Failed to load product: \(error.localizedDescription)"
        }
    }

    // MARK: - Entitlements

    /// Checks current entitlements to see if the user already purchased.
    private func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productId {
                isPurchased = true
                return
            }
        }
        isPurchased = false
    }

    // MARK: - Trial

    /// Records the trial start date if not already set.
    ///
    /// Syncs between UserDefaults and iCloud KV store — whichever has
    /// the earliest date wins (prevents gaming by reinstalling).
    private func ensureTrialStartDate() {
        let ubiquitous = NSUbiquitousKeyValueStore.default
        ubiquitous.synchronize()

        let localDate = UserDefaults.standard.object(forKey: trialStartKey) as? Date
        let cloudDate = ubiquitous.object(forKey: trialStartKey) as? Date

        let trialStart: Date
        if let local = localDate, let cloud = cloudDate {
            // Use the earlier date to prevent gaming
            trialStart = min(local, cloud)
        } else if let existing = localDate ?? cloudDate {
            trialStart = existing
        } else {
            trialStart = Date()
        }

        // Write back to both stores
        UserDefaults.standard.set(trialStart, forKey: trialStartKey)
        ubiquitous.set(trialStart, forKey: trialStartKey)
    }

    /// Returns the trial start date, or nil if never set.
    private var trialStartDate: Date? {
        UserDefaults.standard.object(forKey: trialStartKey) as? Date
    }

    /// Computes trial days remaining from the start date.
    private func computeTrialDaysRemaining() -> Int {
        guard let start = trialStartDate else { return 0 }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, Self.trialDays - elapsed)
    }

    /// Refreshes the composite unlock state from purchase + trial status.
    func refreshUnlockState() {
        let remaining = computeTrialDaysRemaining()
        trialDaysRemaining = remaining
        isTrialActive = !isPurchased && remaining > 0
        isUnlocked = isPurchased || remaining > 0
    }

    // MARK: - Purchase

    /// Initiates the purchase flow for the unlock product.
    func purchase() async {
        guard let product = product else {
            errorMessage = "Product not available. Please try again later."
            return
        }

        isPurchasing = true
        errorMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isPurchased = true
                    refreshUnlockState()
                } else {
                    errorMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }

        isPurchasing = false
    }

    /// Restores previous purchases (required by App Store guidelines).
    func restore() async {
        do {
            try await AppStore.sync()
            await checkEntitlements()
            refreshUnlockState()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Transaction Listener

    /// Listens for transaction updates (renewals, revocations, etc.)
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { @Sendable in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    if transaction.productID == PurchaseManager.productId {
                        await PurchaseManager.shared.markPurchased()
                    }
                }
            }
        }
    }

    /// Called from the detached transaction listener to update state on the main actor.
    fileprivate func markPurchased() {
        isPurchased = true
        refreshUnlockState()
    }

    // MARK: - Formatted Display

    /// Human-readable trial status for the Settings screen.
    var trialStatusText: String {
        if isPurchased { return "Full version purchased" }
        if trialDaysRemaining > 0 {
            return "\(trialDaysRemaining) day\(trialDaysRemaining == 1 ? "" : "s") left in free trial"
        }
        return "Free trial expired"
    }

    /// Formatted price string from StoreKit (e.g. "$2.99").
    var priceText: String {
        product?.displayPrice ?? "$2.99"
    }
}
