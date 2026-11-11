import Foundation
import Testing
@testable import Bookplate

@MainActor
struct SharedWithYouTests {
    private let me = UUID()
    private let maya = UUID()

    private func library(_ access: LibraryInfo.Access) -> LibraryInfo {
        LibraryInfo(id: UUID(), name: "Maya's Favorites", ownerId: access == .owner ? me : maya,
                    ownerName: access == .owner ? "Me" : "Maya Chen", position: 0, access: access)
    }

    private func book(_ id: String) -> Book {
        Book(id: id, title: "Book \(id)", authors: ["A"], pageCount: nil, coverUrl: nil, isbn13: nil)
    }

    private func meta(_ id: String) -> BookMeta {
        BookMeta(bookId: id, status: BookMeta.Status.want, rating: nil, notes: nil, notePhotos: [], tags: [],
                 customCover: nil, addedDate: Date(), startedDate: nil, finishedDate: nil)
    }

    private func store(_ access: LibraryInfo.Access) async throws -> (LibraryStore, InMemoryLibraryRepository, LibrarySync) {
        let snapshot = LibrarySnapshot(books: [book("1"), book("2")], metas: [meta("1"), meta("2")],
                                       shelves: [Shelf(id: "s", name: "Novels", bookIds: ["1", "2"])],
                                       lists: [BookList(id: "l", name: "Club", bookIds: ["1"])])
        let repo = InMemoryLibraryRepository(snapshot)
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: me, sync: sync, localFiles: nil,
                                        coverLookup: NoCoverLookup(), library: library(access))
        return (store, repo, sync)
    }

    // MARK: Review fixes

    @Test func roleChangeUpdatesCanEdit() async throws {
        let (store, _, _) = try await store(.view)
        #expect(!store.canEdit)
        var upgraded = try #require(store.library)
        upgraded.access = .edit
        store.libraryUpdated(upgraded)
        #expect(store.canEdit)
        #expect(!store.isOwned)
    }

    @Test func editorsCantSetCoversOrReuploadThemOnUndo() async throws {
        let (store, _, _) = try await store(.edit)
        store.setCustomCover(URL(fileURLWithPath: "/tmp/c.jpg"), for: "1")
        #expect(store.meta(for: "1")?.customCover == nil)
        // A cover that was already there is dropped on undo instead of uploading into the owner's folder.
        let (owner, _, _) = try await self.store(.owner)
        owner.setCustomCover(URL(fileURLWithPath: "/tmp/c.jpg"), for: "1")
        #expect(owner.meta(for: "1")?.customCover != nil)
        var asEditor = try #require(owner.library)
        asEditor.access = .edit
        owner.libraryUpdated(asEditor)
        owner.removeBook("1")
        _ = owner.undoLastDeletion()
        #expect(owner.book(withId: "1") != nil)
        #expect(owner.meta(for: "1")?.customCover == nil)
    }

    // MARK: View only

    @Test func viewOnlyIgnoresEveryLibraryChange() async throws {
        let (store, repo, sync) = try await store(.view)
        #expect(!store.canEdit)
        #expect(store.addBook(title: "New", author: "X", pageCount: nil, shelfId: "s") == nil)
        #expect(store.addShelf(named: "Another") == nil)
        #expect(!store.deleteShelf("s"))
        #expect(!store.moveBook("2", onShelf: "s", to: 0))
        store.setStatus(BookMeta.Status.read, for: "1")
        store.setRating(5, for: "1")
        store.setNotes("hi", for: "1")
        store.addTag("t", to: "1")
        store.setBook("2", inList: "l", to: true)
        store.deleteList("l")
        #expect(store.addList(named: "Mine") == nil)
        store.setLocked(true, onShelf: "s")
        store.removeBook("1")
        #expect(store.undoLastDeletion() == nil)
        await sync.waitUntilIdle()

        #expect(store.books.count == 2)
        #expect(store.meta(for: "1") == meta("1").withSameDates(as: store.meta(for: "1")))
        #expect(store.bookshelf.shelves == [Shelf(id: "s", name: "Novels", bookIds: ["1", "2"])])
        #expect(store.lists == [BookList(id: "l", name: "Club", bookIds: ["1"])])
        #expect(repo.applied.isEmpty)
    }

    @Test func viewOnlyStillSavesYourOwnSettings() async throws {
        let (store, repo, sync) = try await store(.view)
        store.setReadingGoal(30)
        store.setAppearance(.maple)
        await sync.waitUntilIdle()
        #expect(store.settings.readingGoal == 30)
        #expect(repo.applied.count == 1)
    }

    @Test func canEditLibrariesSaveChanges() async throws {
        let (store, repo, sync) = try await store(.edit)
        #expect(store.canEdit)
        store.setStatus(BookMeta.Status.read, for: "1")
        await sync.waitUntilIdle()
        #expect(store.meta(for: "1")?.status == BookMeta.Status.read)
        #expect(!repo.applied.isEmpty)
    }

    @Test func sampleLibraryCanEdit() {
        #expect(LibraryStore.sample().canEdit)
    }

    // MARK: Bookplate

    @Test func sharedLibraryShowsTheOwnersName() {
        let me = AuthUser(id: me, email: "me@example.com", name: "Tri Nguyen")
        #expect(BookplateBanner.ownerName(me, library: library(.view)) == "Maya Chen")
        #expect(BookplateBanner.ownerName(me, library: library(.edit)) == "Maya Chen")
        #expect(BookplateBanner.ownerName(me, library: library(.owner)) == "Tri Nguyen")
        #expect(BookplateBanner.ownerName(me, library: nil) == "Tri Nguyen")
        var nameless = library(.view)
        nameless.ownerName = " "
        #expect(BookplateBanner.ownerName(me, library: nameless) == nil)
    }

    // MARK: Leaving

    @Test func leavingASharedLibraryOpensYourOwn() async throws {
        let home = LibraryInfo(id: UUID(), name: "Home", ownerId: me, ownerName: "Me", position: 0, access: .owner)
        let shared = library(.view)
        let directory = InMemoryLibraryDirectory(userId: me, libraries: [home, shared])
        let session = LibrarySession(userId: me, ownerName: "Me", directory: directory,
                                     defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        try await session.start()
        session.select(shared.id)
        try await session.leave(shared.id)
        #expect(session.shared.isEmpty)
        #expect(session.current?.id == home.id)
        #expect(directory.items == [home])
        // Your own library can't be "left".
        try await session.leave(home.id)
        #expect(session.owned == [home])
    }

    // MARK: Saving a copy

    @Test func copyProblemMessages() {
        #expect(BookCopyProblem.message(for: .rejected("already_saved"), target: "Home") == "\u{201C}Home\u{201D} already has this book.")
        #expect(BookCopyProblem.message(for: .network, target: "Home").hasPrefix("Couldn't save the book."))
    }

    @Test func inMemoryCopyRecordsTheRequest() async throws {
        let copying = InMemoryBookCopying()
        let source = UUID(), target = UUID()
        try await copying.saveCopy(of: "1", from: source, to: target)
        #expect(copying.copies.count == 1)
        #expect(copying.copies.first?.target == target)
        copying.error = .rejected("already_saved")
        await #expect(throws: BookServiceError.rejected("already_saved")) {
            try await copying.saveCopy(of: "1", from: source, to: target)
        }
    }
}

private extension BookMeta {
    /// Compares ignoring dates (setStatus would have stamped them).
    func withSameDates(as other: BookMeta?) -> BookMeta {
        var copy = self
        copy.startedDate = other?.startedDate
        copy.finishedDate = other?.finishedDate
        return BookMeta(bookId: copy.bookId, status: copy.status, rating: copy.rating, notes: copy.notes,
                        notePhotos: copy.notePhotos, tags: copy.tags, customCover: copy.customCover,
                        addedDate: other?.addedDate ?? copy.addedDate, startedDate: copy.startedDate,
                        finishedDate: copy.finishedDate)
    }
}
