import SwiftUI
import MessageUI

// MARK: - BillHive App (Local / iCloud Target)

/// Entry point for the **BillHive** target — the standalone, iCloud-synced variant.
///
/// Responsibilities:
/// - Creates and owns the `AppViewModel` in local mode (`isLocal: true`).
/// - Migrates existing local data to iCloud on first launch.
/// - Initializes the `PurchaseManager` for IAP and trial management.
/// - Presents the system mail compose sheet (or a copy-paste fallback)
///   when the view model sets `pendingMailCompose`.
/// - Reloads data from iCloud when the app returns to the foreground.
@main
struct BillHiveApp: App {
    @StateObject private var vm = AppViewModel(isLocal: true)
    @StateObject private var purchaseManager = PurchaseManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .environmentObject(purchaseManager)
                .task {
                    CloudStorageManager.shared.migrateLocalToCloudIfNeeded()
                    await purchaseManager.setup()
                    await vm.load()
                }
                .sheet(item: $vm.pendingMailCompose) { req in
                    if MFMailComposeViewController.canSendMail() {
                        MailComposeView(request: req)
                    } else {
                        MailFallbackView(request: req)
                    }
                }
                .sheet(isPresented: $vm.showPaywall) {
                    PaywallView(featureContext: vm.paywallContext)
                }
                .onChange(of: scenePhase) { _ in
                    if scenePhase == .active {
                        purchaseManager.refreshUnlockState()
                        Task { await vm.reloadFromCloud() }
                    }
                }
        }
    }
}
