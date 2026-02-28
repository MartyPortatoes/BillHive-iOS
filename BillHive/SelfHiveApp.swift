import SwiftUI

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
