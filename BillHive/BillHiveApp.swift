import SwiftUI
import MessageUI

// MARK: - BillHive App (Local / iCloud Target)

/// Entry point for the **BillHive** target — the standalone, iCloud-synced variant.
///
/// Responsibilities:
/// - Creates and owns the `AppViewModel` in local mode (`isLocal: true`).
/// - Migrates existing local data to iCloud on first launch.
/// - Presents the system mail compose sheet (or a copy-paste fallback)
///   when the view model sets `pendingMailCompose`.
/// - Reloads data from iCloud when the app returns to the foreground.
@main
struct BillHiveApp: App {
    @StateObject private var vm = AppViewModel(isLocal: true)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .task {
                    CloudStorageManager.shared.migrateLocalToCloudIfNeeded()
                    await vm.load()
                }
                .sheet(item: $vm.pendingMailCompose) { req in
                    if MFMailComposeViewController.canSendMail() {
                        MailComposeView(request: req)
                    } else {
                        MailFallbackView(request: req)
                    }
                }
                .onChange(of: scenePhase) { _ in
                    if scenePhase == .active {
                        Task { await vm.reloadFromCloud() }
                    }
                }
        }
    }
}
