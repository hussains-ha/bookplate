import SwiftUI

@main struct MyApp: App {
    @State private var store = LibraryStore.sample()
    @State private var auth = AuthService(backend: SupabaseAuthBackend())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(auth)
                .task { await store.backfillCovers() }
                .task { await auth.observeSession() }
        }
    }
}
