import SwiftUI

/// Loads the signed-in user's library from Supabase, then shows the app.
/// Changes left over from a previous session that never reached the server are shown and sent again.
struct SignedInLibraryView: View {
    let user: AuthUser
    var makeRepository: ((UUID) -> LibraryRepository) = { SupabaseLibraryRepository(userId: $0) }

    @Environment(AuthService.self) private var auth
    @State private var phase = Phase.loading
    /// Titles of books that hadn't finished saving last time.
    @State private var unsavedTitles: [String] = []

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
                // Signing out (or switching accounts) ends this library's saving.
                .onDisappear { store.stopSync() }
                .alert(Self.unsavedTitle(unsavedTitles.count), isPresented: Binding(
                    get: { !unsavedTitles.isEmpty },
                    set: { if !$0 { unsavedTitles = [] } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(Self.unsavedMessage(unsavedTitles))
                }
        }
    }

    static func unsavedTitle(_ count: Int) -> String {
        count == 1 ? "1 book hadn't finished saving" : "\(count) books hadn't finished saving"
    }

    static func unsavedMessage(_ titles: [String]) -> String {
        let names = titles.prefix(3).map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")
        let more = titles.count > 3 ? " and \(titles.count - 3) more" : ""
        return "\(names)\(more) didn't reach your online library last time. Saving now."
    }

    private func load() async {
        await CoverImageLoader.shared.setStorage(SupabaseCoverStorage(client: SupabaseService.client))
        let repository = makeRepository(user.id)
        let pendingFile = try? PendingChangesFile.forUser(user.id)
        let leftover = pendingFile?.load() ?? []
        do {
            var snapshot = try await repository.loadLibrary()
            let (unsaved, toSend) = snapshot.replay(leftover)
            let sync = LibrarySync(repository: repository, pendingFile: pendingFile)
            let store = LibraryStore.loaded(snapshot, userId: user.id, sync: sync,
                                            localFiles: try? LocalBookFiles.forUser(user.id))
            sync.enqueue(contentsOf: toSend)
            // After the leftovers, so fixes never jump ahead of changes they depend on.
            store.saveOneCopyRepairs()
            unsavedTitles = unsaved.map(\.title)
            phase = .ready(store)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
