import SwiftUI

/// Loads the signed-in user's libraries, then the open one from Supabase, then shows the app.
/// Changes left over from a previous session that never reached the server are shown and sent again.
struct SignedInLibraryView: View {
    let user: AuthUser
    var makeRepository: ((UUID, LibraryInfo) -> LibraryRepository) = { SupabaseLibraryRepository(user: $0, library: $1) }
    var makeDirectory: ((UUID) -> LibraryDirectory) = { SupabaseLibraryDirectory(userId: $0) }

    @Environment(AuthService.self) private var auth
    @State private var session: LibrarySession?
    @State private var phase = Phase.loading
    /// Titles of books that hadn't finished saving last time.
    @State private var unsavedTitles: [String] = []
    /// Bumped by "Try again" to rerun loading.
    @State private var attempt = 0

    private enum Phase {
        case loading
        case failed(String)
        case ready(LibraryStore)
    }

    var body: some View {
        content
            .environment(session)
            // First the list of libraries, then whichever one is open (again whenever it changes).
            .task(id: StartKey(user: user.id, attempt: attempt)) { await startSession() }
            .task(id: LoadKey(library: session?.currentId, attempt: attempt)) { await loadLibrary() }
    }

    private struct StartKey: Equatable {
        let user: UUID
        let attempt: Int
    }

    private struct LoadKey: Equatable {
        let library: UUID?
        let attempt: Int
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading your library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
        case .failed(let message):
            VStack(spacing: 12) {
                Text("Couldn't load your library")
                    .font(Theme.title(22))
                    .foregroundStyle(Theme.brown)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedText)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    phase = .loading
                    attempt += 1
                }
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
                .id(store.library?.id)
                .task { await store.backfillCovers() }
                // Signing out, switching accounts or switching libraries ends this library's saving.
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

    private func startSession() async {
        await CoverImageLoader.shared.setStorage(SupabaseCoverStorage(client: SupabaseService.client))
        if let session, session.userId == user.id, session.current != nil { return }
        let new = LibrarySession(userId: user.id, ownerName: user.name, directory: makeDirectory(user.id))
        do {
            try await new.start()
            guard !Task.isCancelled else { return }
            session = new
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadLibrary() async {
        guard let session, let library = session.current else { return }
        if case .ready(let store) = phase, store.library?.id == library.id { return }
        phase = .loading
        let repository = makeRepository(user.id, library)
        let pendingFile = try? PendingChangesFile.forLibrary(library.id, user: user.id)
        // Changes saved before there were several libraries belong to the first one you own.
        let legacy = library.id == session.owned.first?.id ? try? PendingChangesFile.forUser(user.id) : nil
        let leftover = (legacy?.load() ?? []) + (pendingFile?.load() ?? [])
        do {
            var snapshot = try await repository.loadLibrary()
            // Switched away while loading: the newer load takes over.
            guard !Task.isCancelled, session.currentId == library.id else { return }
            let (unsaved, toSend) = snapshot.replay(leftover)
            let sync = LibrarySync(repository: repository, pendingFile: pendingFile)
            let store = LibraryStore.loaded(snapshot, userId: user.id, sync: sync,
                                            localFiles: try? LocalBookFiles.forUser(user.id), library: library)
            sync.enqueue(contentsOf: toSend)
            legacy?.save([])
            // After the leftovers, so fixes never jump ahead of changes they depend on.
            store.saveOneCopyRepairs()
            unsavedTitles = unsaved.map(\.title)
            phase = .ready(store)
        } catch {
            guard !Task.isCancelled, session.currentId == library.id else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
