import SwiftUI

// MARK: - SelfHive App (Remote Server Target)

/// Entry point for the **SelfHive** target — the self-hosted server variant.
///
/// If no server URL has been configured yet, presents `ServerSetupView` for
/// initial onboarding. Once a URL is saved in `@AppStorage("serverURL")`,
/// the app shows `ContentView` and loads data from the remote server.
@main
struct SelfHiveApp: App {
    @StateObject private var vm = AppViewModel()
    @AppStorage("serverURL") private var serverURL: String = ""

    var body: some Scene {
        WindowGroup {
            if serverURL.isEmpty {
                ServerSetupView()
                    .environmentObject(vm)
            } else {
                ContentView()
                    .environmentObject(vm)
                    .task { await vm.load() }
            }
        }
    }
}
