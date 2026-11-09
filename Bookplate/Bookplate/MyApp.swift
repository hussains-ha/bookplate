import SwiftUI

@main struct MyApp: App {
    @State private var auth = AuthService(backend: SupabaseAuthBackend())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .task { await auth.observeSession() }
        }
    }
}
