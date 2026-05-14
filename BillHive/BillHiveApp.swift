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
    @State private var showLockedPaywall = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .environmentObject(purchaseManager)
                .task {
                    let migration = CloudStorageManager.shared.migrateLocalToCloudIfNeeded()
                    await purchaseManager.setup()
                    await vm.load()
                    if migration == .localCorrupt {
                        vm.toast("Local data couldn't be read; it wasn't migrated to iCloud. Restore from a backup if you have one.")
                    }
                    if !purchaseManager.isUnlocked {
                        showLockedPaywall = true
                    }
                }
                .sheet(item: $vm.pendingMailCompose) { req in
                    if MFMailComposeViewController.canSendMail() {
                        MailComposeView(request: req)
                    } else {
                        MailFallbackView(request: req)
                    }
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
                        Task { await vm.reloadFromCloud() }
                    }
                }
        }
    }
}
