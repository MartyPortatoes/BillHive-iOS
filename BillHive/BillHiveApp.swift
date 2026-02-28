import SwiftUI
import MessageUI

@main
struct BillHiveApp: App {
    @StateObject private var vm = AppViewModel(isLocal: true)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .task { await vm.load() }
                .sheet(item: $vm.pendingMailCompose) { req in
                    if MFMailComposeViewController.canSendMail() {
                        MailComposeView(request: req)
                    } else {
                        MailFallbackView(request: req)
                    }
                }
        }
    }
}
