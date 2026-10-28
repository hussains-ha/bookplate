import SwiftUI

@main struct MyApp: App {
    @State private var store = LibraryStore.sample()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .task { await store.backfillCovers() }
        }
    }
}
