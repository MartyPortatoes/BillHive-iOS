import SwiftUI

// MARK: - SelfHive App (Remote Server Target)

/// Entry point for the **SelfHive** target — the self-hosted server variant.
///
/// If no server URL has been configured yet, presents `ServerSetupView` for
/// initial onboarding. Once a URL is saved, the app shows `ContentView` and
/// loads data from the remote server. After the 14-day trial, a non-dismissible
/// paywall locks the entire app until the user purchases.
@main
struct SelfHiveApp: App {
    @StateObject private var vm = AppViewModel()
    @StateObject private var purchaseManager = PurchaseManager.shared
    @AppStorage("serverURL") private var serverURL: String = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLockedPaywall = false

    var body: some Scene {
        WindowGroup {
            if serverURL.isEmpty {
                ServerSetupView()
                    .environmentObject(vm)
            } else {
                ContentView()
                    .environmentObject(vm)
                    .environmentObject(purchaseManager)
                    .task {
                        await purchaseManager.setup()
                        await vm.load()
                        if !purchaseManager.isUnlocked {
                            showLockedPaywall = true
                        }
                    }
                    .sheet(isPresented: $vm.showPaywall) {
                        PaywallView(featureContext: vm.paywallContext)
                    }
                    .fullScreenCover(isPresented: $showLockedPaywall) {
                        PaywallView(allowDismiss: false)
                    }
                    .onChange(of: purchaseManager.isUnlocked) { unlocked in
                        if unlocked { showLockedPaywall = false }
                    }
                    .onChange(of: scenePhase) { _ in
                        if scenePhase == .active {
                            purchaseManager.refreshUnlockState()
                            if !purchaseManager.isUnlocked && !showLockedPaywall {
                                showLockedPaywall = true
                            }
                        }
                    }
            }
        }
    }
}
