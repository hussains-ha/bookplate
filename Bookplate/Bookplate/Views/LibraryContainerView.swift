import SwiftUI

/// Loads the signed-in user's library from Supabase, then shows the app.
struct SignedInLibraryView: View {
    let user: AuthUser
    var makeRepository: () -> LibraryRepository = { SupabaseLibraryRepository() }

    @Environment(AuthService.self) private var auth
    @State private var phase = Phase.loading

    private enum Phase {
        case loading
        case failed(String)
        case ready(LibraryStore)
    }

    var body: some View {
        switch phase {
        case .loading:
            ProgressView("Loading your library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
                .task(id: user.id) { await load() }
        case .failed(let message):
            VStack(spacing: 12) {
                Text("Couldn't load your library")
                    .font(Theme.title(22))
                    .foregroundStyle(Theme.brown)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
                Button("Try again") { phase = .loading }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brown)
                Button("Sign out") { Task { await auth.signOut() } }
                    .font(.footnote)
                    .foregroundStyle(Theme.brown)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
        case .ready(let store):
            MainTabView()
                .environment(store)
                .task { await store.backfillCovers() }
        }
    }

    private func load() async {
        let repository = makeRepository()
        do {
            let snapshot = try await repository.loadLibrary()
            let store = LibraryStore.loaded(snapshot, userId: user.id, sync: LibrarySync(repository: repository),
                                            localFiles: try? LocalBookFiles.forUser(user.id))
            phase = .ready(store)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

/// "Skip to library (dev)": the bundled sample library, kept in memory only.
struct SampleLibraryView: View {
    @State private var store = LibraryStore.sample()

    var body: some View {
        MainTabView()
            .environment(store)
            .task { await store.backfillCovers() }
    }
}
