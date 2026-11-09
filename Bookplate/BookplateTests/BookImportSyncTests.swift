import Foundation
import Testing
@testable import Bookplate

@MainActor
struct BookImportSyncTests {
    private let folder: URL
    private let pendingFile: PendingChangesFile

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pendingFile = PendingChangesFile(fileURL: folder.appendingPathComponent("pending.json"))
    }

    private func book(_ id: String, _ title: String = "Dune", author: String = "Frank Herbert") -> Book {
        Book(id: id, title: title, authors: [author], pageCount: nil, coverUrl: nil, isbn13: nil)
    }

    private func store(_ repo: LibraryRepository, pendingFile: PendingChangesFile? = nil,
                       snapshot: LibrarySnapshot? = nil) -> (LibraryStore, LibrarySync) {
        // A retry wait that never ends on its own, like being offline for a long time.
        let sync = LibrarySync(repository: repo, pendingFile: pendingFile, retryDelays: [.seconds(3600)],
                               sleep: { try await Task.sleep(for: $0) })
        return (LibraryStore.loaded(snapshot ?? LibrarySnapshot(), userId: UUID(), sync: sync, localFiles: nil, coverLookup: NoCoverLookup()), sync)
    }

    // MARK: Pending changes on disk

    @Test func pendingFileRoundTripsEveryChange() {
        let changes: [LibraryChange] = [
            .saveBook(book("b1")), .deleteBook(id: "b2"), .saveMeta(BookMeta.mocks[0]),
            .saveShelf(Shelf(id: "s", name: "S", bookIds: [], isLocked: true), position: 2),
            .setShelfBooks(shelfId: "s", bookIds: ["b1"]),
            .saveList(BookList(id: "l", name: "L", bookIds: []), position: 0),
            .setListBooks(listId: "l", bookIds: []),
        ]
        pendingFile.save(changes)
        #expect(pendingFile.load() == changes)
        pendingFile.save([])
        #expect(!FileManager.default.fileExists(atPath: pendingFile.fileURL.path))
    }

    @Test func queueIsWrittenToDiskUntilSaved() async {
        let repo = InMemoryLibraryRepository()
        let sync = LibrarySync(repository: repo, pendingFile: pendingFile, retryDelays: [.zero], sleep: { _ in })
        sync.enqueue(.saveBook(book("b1")))
        #expect(pendingFile.load() == [.saveBook(book("b1"))])
        await sync.waitUntilIdle()
        #expect(pendingFile.load().isEmpty)
    }

    /// Add a book while offline, "quit", relaunch: the book shows, the user is told, and it gets saved.
    @Test func unsavedBooksAreReplayedAfterRelaunch() async throws {
        let server = InMemoryLibraryRepository()
        let offline = FlakyLibraryRepository(server, failures: .max)
        let (first, firstSync) = store(offline, pendingFile: pendingFile)
        let added = try #require(first.addBook(title: "Dune", author: "Frank Herbert", pageCount: nil, shelfId: nil))
        while firstSync.status == .saving || firstSync.status == .idle { await Task.yield() }
        #expect(server.snapshot.books.isEmpty)   // never reached the server
        firstSync.retryNow()                     // "quit": drop the in-memory session

        // Relaunch, now online.
        var snapshot = try await server.loadLibrary()
        let leftover = pendingFile.load()
        let (unsaved, toSend) = snapshot.replay(leftover)
        #expect(unsaved.map(\.id) == [added.id])
        let sync = LibrarySync(repository: server, pendingFile: pendingFile, retryDelays: [.zero], sleep: { _ in })
        let relaunched = LibraryStore.loaded(snapshot, userId: UUID(), sync: sync, localFiles: nil, coverLookup: NoCoverLookup())
        #expect(relaunched.book(withId: added.id) != nil)
        #expect(relaunched.bookshelf.shelves.first?.bookIds == [added.id])
        sync.enqueue(contentsOf: toSend)
        await sync.waitUntilIdle()
        #expect(server.snapshot.books.map(\.id) == [added.id])
        #expect(server.snapshot.shelves.first?.bookIds == [added.id])
        #expect(pendingFile.load().isEmpty)
    }

    @Test func replayDoesNotReportBooksTheServerAlreadyHas() {
        var snapshot = LibrarySnapshot(books: [book("b1")])
        #expect(snapshot.replay([.saveBook(book("b1"))]).missing.isEmpty)
    }

    @Test func replayIgnoresBooksAddedAndDeletedBeforeSaving() {
        var snapshot = LibrarySnapshot()
        #expect(snapshot.replay([.saveBook(book("b1")), saveMeta("b1"), .deleteBook(id: "b1")]).missing.isEmpty)
        #expect(snapshot.books.isEmpty)
    }

    private func saveMeta(_ bookId: String) -> LibraryChange {
        .saveMeta(BookMeta(bookId: bookId, status: "want", rating: nil, notes: nil, notePhotos: [], tags: [],
                           customCover: nil, addedDate: Date(timeIntervalSince1970: 0), startedDate: nil, finishedDate: nil))
    }

    /// Book deleted on another device while this one still had a cover update queued for it.
    @Test func replayDoesNotResurrectBooksDeletedElsewhere() {
        var snapshot = LibrarySnapshot(shelves: [Shelf(id: "s", name: "S", bookIds: [])])
        let (missing, toSend) = snapshot.replay([.saveBook(book("gone")), saveMeta("gone"), .deleteBook(id: "x"),
                                                 .setShelfBooks(shelfId: "s", bookIds: ["gone"])].filter {
            if case .saveMeta = $0 { false } else { true }
        })
        #expect(missing.isEmpty)
        #expect(snapshot.books.isEmpty)
        #expect(!toSend.contains(.saveBook(book("gone"))))
    }

    @Test func replayResendsBooksAddedOnThisDevice() {
        var snapshot = LibrarySnapshot()
        let (missing, toSend) = snapshot.replay([.saveBook(book("new")), saveMeta("new")])
        #expect(missing.map(\.id) == ["new"])
        #expect(toSend.count == 2)
    }

    @Test func unreadablePendingEntriesAreSkipped() throws {
        let good = try JSONEncoder().encode([LibraryChange.deleteBook(id: "b1")])
        var array = try JSONSerialization.jsonObject(with: good) as! [Any]
        array.insert(["someFutureCase": ["x": 1]], at: 0)
        try JSONSerialization.data(withJSONObject: array).write(to: pendingFile.fileURL)
        #expect(pendingFile.load() == [.deleteBook(id: "b1")])
    }

    @Test func unreadablePendingFileIsBackedUpNotOverwritten() throws {
        try Data("not json".utf8).write(to: pendingFile.fileURL)
        #expect(pendingFile.load().isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("unreadable") }
        #expect(backups.count == 1)
    }

    @Test func unsavedAlertText() {
        #expect(SignedInLibraryView.unsavedTitle(1) == "1 book hadn't finished saving")
        #expect(SignedInLibraryView.unsavedTitle(2) == "2 books hadn't finished saving")
        let message = SignedInLibraryView.unsavedMessage(["A", "B", "C", "D", "E"])
        #expect(message.contains("“A”, “B”, “C” and 2 more"))
    }

    // MARK: Duplicate check

    @Test func duplicateCheckAsksTheServer() async {
        // On the server but not loaded on this device (e.g. added from another phone).
        let server = InMemoryLibraryRepository(LibrarySnapshot(books: [book("remote", "Dune")]))
        let (store, _) = store(server)
        let check = await store.checkDuplicate(title: " dune ", author: "frank herbert")
        #expect(check == LibraryStore.DuplicateCheck(match: book("remote", "Dune"), checkedDeviceOnly: false))
    }

    @Test func duplicateCheckMatchesAuthorAfterServerSearch() async {
        let server = InMemoryLibraryRepository(LibrarySnapshot(books: [book("remote", "Dune", author: "Someone Else")]))
        let (store, _) = store(server)
        #expect(await store.checkDuplicate(title: "Dune", author: "Frank Herbert").match == nil)
        #expect(await store.checkDuplicate(title: "Dune", author: "").match?.id == "remote")
    }

    @Test func duplicateCheckFallsBackToDeviceWhenOffline() async {
        let server = InMemoryLibraryRepository()
        server.searchError = .network
        let (store, _) = store(server, snapshot: LibrarySnapshot(books: [book("local", "Émma", author: "Jane Austen")]))
        let check = await store.checkDuplicate(title: "emma", author: "jane austen")
        #expect(check.match?.id == "local")
        #expect(check.checkedDeviceOnly)
    }

    @Test func duplicateCheckIncludesBooksNotYetSaved() async throws {
        let server = InMemoryLibraryRepository()
        let offline = FlakyLibraryRepository(server, failures: .max)
        let (store, _) = store(offline)
        let added = try #require(store.addBook(title: "Dune", author: "Frank Herbert", pageCount: nil, shelfId: nil))
        #expect(await store.checkDuplicate(title: "Dune", author: "Frank Herbert").match?.id == added.id)
    }

    @Test func sampleLibraryChecksLocallyOnly() async throws {
        let store = LibraryStore.sample()
        let first = try #require(store.books.first)
        let check = await store.checkDuplicate(title: first.title, author: first.authors.first ?? "")
        #expect(check.match?.id == first.id)
        #expect(!check.checkedDeviceOnly)
    }

    @Test func likePatternsAreEscaped() {
        #expect(SupabaseLibraryRepository.escapeLike(#"100% _real_ a\b"#) == #"100\% \_real\_ a\\b"#)
    }
}
