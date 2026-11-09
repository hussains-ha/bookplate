import Foundation
import Supabase
import Testing
@testable import Bookplate

/// Fails the first `failures` applies with `error`, then delegates to an in-memory repository.
@MainActor
final class FlakyLibraryRepository: LibraryRepository {
    let inner: InMemoryLibraryRepository
    var failures: Int
    var error: BookServiceError

    init(_ inner: InMemoryLibraryRepository? = nil, failures: Int = 0, error: BookServiceError = .network) {
        self.inner = inner ?? InMemoryLibraryRepository()
        self.failures = failures
        self.error = error
    }

    func loadLibrary() async throws(BookServiceError) -> LibrarySnapshot { try await inner.loadLibrary() }

    func books(titled title: String) async throws(BookServiceError) -> [Book] {
        try await inner.books(titled: title)
    }

    func apply(_ change: LibraryChange) async throws(BookServiceError) {
        if failures > 0 {
            failures -= 1
            throw error
        }
        try await inner.apply(change)
    }
}

/// Cover lookups that never find anything and never touch the network.
struct NoCoverLookup: CoverLookup {
    func lookup(title: String, author: String?, isbn: String?) async throws -> CoverLookupResult? {
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor
struct LibrarySyncTests {
    private let book = Book(id: "book-1", title: "One", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil)

    private func sync(_ repository: LibraryRepository) -> LibrarySync {
        LibrarySync(repository: repository, retryDelays: [.zero], sleep: { _ in })
    }

    @Test func savesChangesInOrder() async {
        let repo = InMemoryLibraryRepository()
        let sync = sync(repo)
        sync.enqueue(.saveBook(book))
        sync.enqueue(.saveShelf(Shelf(id: "s", name: "S", bookIds: []), position: 0))
        sync.enqueue(.setShelfBooks(shelfId: "s", bookIds: ["book-1"]))
        await sync.waitUntilIdle()
        #expect(repo.applied.count == 3)
        #expect(repo.snapshot.shelves.first?.bookIds == ["book-1"])
        #expect(sync.pending.isEmpty)
        #expect(sync.status == .idle)
    }

    @Test func retriesFailedChangesUntilTheySave() async {
        let repo = FlakyLibraryRepository(failures: 3)
        let sync = sync(repo)
        sync.enqueue(.saveBook(book))
        await sync.waitUntilIdle()
        #expect(repo.inner.snapshot.books == [book])
        #expect(sync.status == .idle)
    }

    @Test func showsRetryingWhileFailing() async {
        let repo = FlakyLibraryRepository(failures: 1)
        var seen: [LibrarySync.Status] = []
        var sync: LibrarySync!
        sync = LibrarySync(repository: repo, retryDelays: [.zero], sleep: { _ in seen.append(sync.status) })
        sync.enqueue(.saveBook(book))
        await sync.waitUntilIdle()
        #expect(seen == [.retrying(BookServiceError.network.localizedDescription)])
    }

    @Test func dropsRejectedChangesAndKeepsGoing() async {
        let repo = InMemoryLibraryRepository()
        let sync = sync(repo)
        sync.enqueue(.setShelfBooks(shelfId: "missing", bookIds: []))
        sync.enqueue(.saveBook(book))
        await sync.waitUntilIdle()
        #expect(repo.snapshot.books == [book])
        guard case .rejected = sync.status else {
            Issue.record("expected a rejection notice, got \(sync.status)")
            return
        }
        sync.dismissRejection()
        #expect(sync.status == .idle)
    }

    @Test func retryNowSkipsTheWait() async {
        let repo = FlakyLibraryRepository(failures: 1)
        var sync: LibrarySync!
        // A wait that only ends when cancelled.
        sync = LibrarySync(repository: repo, retryDelays: [.seconds(3600)], sleep: { duration in
            try await Task.sleep(for: duration)
        })
        sync.enqueue(.saveBook(book))
        while sync.status == .saving || sync.status == .idle { await Task.yield() }
        sync.retryNow()
        await sync.waitUntilIdle()
        #expect(repo.inner.snapshot.books == [book])
    }
}

@MainActor
struct LibraryStoreSyncTests {
    private func makeStore(_ repo: InMemoryLibraryRepository) async throws -> (LibraryStore, LibrarySync) {
        let sync = LibrarySync(repository: repo, retryDelays: [.zero], sleep: { _ in })
        let snapshot = try await repo.loadLibrary()
        return (LibraryStore.loaded(snapshot, userId: UUID(), sync: sync, localFiles: nil, coverLookup: NoCoverLookup()), sync)
    }

    @Test func newAccountStartsEmpty() async throws {
        let (store, _) = try await makeStore(InMemoryLibraryRepository())
        #expect(store.books.isEmpty)
        #expect(store.bookshelf.shelves.isEmpty)
        #expect(store.lists.isEmpty)
    }

    /// Every kind of change survives a save and a fresh load.
    @Test func changesRoundTripThroughTheRepository() async throws {
        let repo = InMemoryLibraryRepository()
        let (store, sync) = try await makeStore(repo)

        let dune = try #require(store.addBook(title: "Dune", author: "Frank Herbert", pageCount: 688, shelfId: nil))
        let emma = try #require(store.addBook(title: "Emma", author: "Jane Austen", pageCount: nil, shelfId: nil))
        let gone = try #require(store.addBook(title: "Gone", author: "", pageCount: nil, shelfId: nil))
        let shelfId = try #require(store.bookshelf.shelves.first?.id)
        store.moveBook(dune.id, onShelf: shelfId, to: 0)
        store.setStatus(BookMeta.Status.reading, for: dune.id)
        store.setRating(5, for: dune.id)
        store.setNotes("Spice", for: dune.id)
        store.addTag("sci-fi", to: dune.id)
        store.addTag("classic", to: emma.id)
        store.removeTag("classic", from: emma.id)
        store.addList(BookList(id: "list-1", name: "Favorites", bookIds: []))
        store.setBook(dune.id, inList: "list-1", to: true)
        store.setBook(emma.id, inList: "list-1", to: true)
        store.setLocked(true, onShelf: shelfId)
        store.removeBook(gone.id)
        await sync.waitUntilIdle()
        #expect(sync.status == .idle)

        let (reloaded, _) = try await makeStore(repo)
        #expect(Set(reloaded.books) == Set(store.books))
        #expect(Set(reloaded.metas) == Set(store.metas))
        #expect(reloaded.bookshelf.shelves == store.bookshelf.shelves)
        #expect(reloaded.lists == store.lists)
        #expect(reloaded.bookshelf.shelves.first?.bookIds == [dune.id, emma.id])
        #expect(reloaded.meta(for: dune.id)?.tags == ["sci-fi"])
        #expect(reloaded.bookshelf.shelves.first?.isLocked == true)
    }

    @Test func unchangedValuesAreNotSaved() async throws {
        let repo = InMemoryLibraryRepository()
        let (store, sync) = try await makeStore(repo)
        let book = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: nil))
        await sync.waitUntilIdle()
        let saved = repo.applied.count
        store.setStatus(BookMeta.Status.want, for: book.id)   // already "want"
        store.setRating(9, for: book.id)                      // invalid
        store.addTag("  ", to: book.id)                       // blank
        store.setBook(book.id, inList: "missing", to: true)   // no such list
        await sync.waitUntilIdle()
        #expect(repo.applied.count == saved)
    }

    @Test func coversAndNotePhotosStayLocal() async throws {
        let repo = InMemoryLibraryRepository()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = LocalBookFiles(fileURL: folder.appendingPathComponent("local.json"), imagesFolder: folder)
        let sync = LibrarySync(repository: repo, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(LibrarySnapshot(), userId: UUID(), sync: sync, localFiles: files,
                                        coverLookup: NoCoverLookup())
        let book = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: nil))
        await sync.waitUntilIdle()
        let saved = repo.applied.count

        store.setCustomCover(folder.appendingPathComponent("cover.jpg"), for: book.id)
        store.addNotePhoto(folder.appendingPathComponent("note.jpg"), to: book.id)
        await sync.waitUntilIdle()
        #expect(repo.applied.count == saved)   // nothing sent to the server
        #expect(repo.snapshot.metas.first?.customCover == nil)

        let reloaded = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                           localFiles: files, coverLookup: NoCoverLookup())
        #expect(reloaded.meta(for: book.id)?.customCover?.lastPathComponent == "cover.jpg")
        #expect(reloaded.meta(for: book.id)?.notePhotos.map(\.lastPathComponent) == ["note.jpg"])
    }

    @Test func sampleLibraryHasNoSync() {
        let store = LibraryStore.sample()
        store.setLocked(true, onShelf: store.bookshelf.shelves[0].id)
        #expect(store.syncStatus == .idle)
    }
}

struct LibraryRowTests {
    private let encoder = PostgrestClient.Configuration.jsonEncoder
    private let decoder = PostgrestClient.Configuration.jsonDecoder

    @Test func metaRowRoundTripsWithoutLocalFields() throws {
        var meta = BookMeta.mocks[0]
        meta.customCover = URL(string: "file:///cover.jpg")
        meta.notePhotos = [URL(string: "file:///note.jpg")!]
        let row = try decoder.decode(BookMetaRow.self, from: encoder.encode(BookMetaRow(meta)))
        #expect(row.meta.bookId == meta.bookId)
        #expect(row.meta.tags == meta.tags)
        #expect(abs(row.meta.addedDate.timeIntervalSince(meta.addedDate)) < 0.001)
        #expect(row.meta.customCover == nil)
        #expect(row.meta.notePhotos.isEmpty)
    }

    @Test func decodesDatabaseTimestamps() throws {
        let json = #"{"book_id":"b","status":"read","rating":null,"notes":null,"tags":[],"added_at":"2026-11-09T05:28:22.107+00:00","started_at":null,"finished_at":"2026-11-10T00:00:00+00:00"}"#
        let meta = try decoder.decode(BookMetaRow.self, from: Data(json.utf8)).meta
        #expect(meta.status == "read")
        #expect(meta.finishedDate != nil)
    }

    @Test func membershipRowsUseTheirTablesColumn() throws {
        let shelfRow = MembershipRow(collectionId: "s", bookId: "b", position: 1, idColumn: "shelf_id")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(shelfRow)) as? [String: Any]
        #expect(json?["shelf_id"] as? String == "s")
        let decoded = try JSONDecoder().decode(MembershipRow.self, from: Data(#"{"list_id":"l","book_id":"b","position":0}"#.utf8))
        #expect(decoded.idColumn == "list_id")
        #expect(decoded.collectionId == "l")
    }

    @Test func snapshotOrdersShelvesAndBooksAndSkipsUnknownBooks() {
        let books = [BookRow(.mock)]
        let snapshot = LibrarySnapshot(
            books: books, metas: [],
            shelves: [CollectionRow(id: "s2", name: "Two", position: 1, isLocked: true),
                      CollectionRow(id: "s1", name: "One", position: 0, isLocked: false)],
            shelfBooks: [MembershipRow(collectionId: "s1", bookId: "ghost", position: 0, idColumn: "shelf_id"),
                         MembershipRow(collectionId: "s1", bookId: Book.mock.id, position: 1, idColumn: "shelf_id")],
            lists: [], listBooks: [])
        #expect(snapshot.shelves.map(\.id) == ["s1", "s2"])
        #expect(snapshot.shelves[0].bookIds == [Book.mock.id])
        #expect(snapshot.shelves[1].isLocked)
    }
}
