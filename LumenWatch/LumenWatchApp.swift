import SwiftUI

@main
struct LumenWatchApp: App {
    @StateObject private var store = WatchStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .onAppear { store.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await store.refreshActivity() }
                        if store.isStale { store.requestSnapshot() }
                    }
                }
        }
    }
}
