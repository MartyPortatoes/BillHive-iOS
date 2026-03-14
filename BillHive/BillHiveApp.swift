import SwiftUI
import MessageUI

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
