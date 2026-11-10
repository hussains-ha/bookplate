import Foundation
import Testing
@testable import Bookplate

@MainActor
struct UndoDeletionTests {
    private func book(_ id: String) -> Book {
        Book(id: id, title: "Title \(id)", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil)
    }

    private func meta(_ id: String) -> BookMeta {
        BookMeta(bookId: id, status: BookMeta.Status.reading, rating: 4, notes: "Notes \(id)",
                 notePhotos: [URL(fileURLWithPath: "/tmp/\(id).jpg")], tags: ["t1", "t2"],
                 customCover: URL(fileURLWithPath: "/tmp/cover-\(id).jpg"),
                 addedDate: Date(timeIntervalSince1970: 1), startedDate: nil, finishedDate: nil)
    }

    private func snapshot() -> LibrarySnapshot {
        let ids = ["1", "2", "3", "4"]
        return LibrarySnapshot(
            books: ids.map(book), metas: ids.map(meta),
            shelves: [Shelf(id: "a", name: "A", bookIds: ["1", "2"]),
                      Shelf(id: "b", name: "B", bookIds: ["3", "2"], isLocked: true),
                      Shelf(id: "c", name: "C", bookIds: ["4"])],
            lists: [BookList(id: "l", name: "L", bookIds: ["4", "2"])]
        )
    }

    private func store(sync: LibrarySync? = nil) -> LibraryStore {
        let s = snapshot()
        return LibraryStore(books: s.books, metas: s.metas,
                            bookshelf: Bookshelf(id: "bs", name: "BS", shelves: s.shelves, appearance: .classic),
                            lists: s.lists, coverLookup: NoCoverLookup(), sync: sync)
    }

    @Test func restoresARemovedBookWithItsDetailsShelvesAndLists() throws {
        let store = store()
        let before = (store.bookshelf.shelves, store.lists, store.metas)
        store.removeBook("2")
        #expect(store.book(withId: "2") == nil)
        let undone = try #require(store.undoLastDeletion())
        #expect(undone.name == "Title 2")
        #expect(store.book(withId: "2") == book("2"))
        #expect(store.meta(for: "2") == meta("2"))      // status, rating, notes, tags, photos, cover
        #expect(store.bookshelf.shelves == before.0)    // same spot on both shelves, even the locked one
        #expect(store.lists == before.1)
        #expect(Set(store.metas.map(\.bookId)) == Set(before.2.map(\.bookId)))
        #expect(store.undoStack.isEmpty)
    }

    @Test func restoresADeletedShelfInPlaceWithItsBooks() {
        let store = store()
        let before = store.bookshelf.shelves
        #expect(store.deleteShelf("c"))                // "4" moves to A
        #expect(store.bookshelf.shelves[0].bookIds == ["1", "2", "4"])
        store.undoLastDeletion()
        #expect(store.bookshelf.shelves == before)
    }

    @Test func undoingAShelfOnlyTakesBackBooksThatWereMoved() {
        let store = store()
        store.addShelf(named: "D")
        store.addBook(title: "New", author: "", pageCount: nil, shelfId: store.bookshelf.shelves[3].id)
        let newId = store.bookshelf.shelves[3].bookIds[0]
        store.setLocked(true, onShelf: "b")
        // D's book moves to A; then A gets another book; undo must leave that one.
        #expect(store.deleteShelf(store.bookshelf.shelves[3].id))
        store.addBook(title: "Later", author: "", pageCount: nil, shelfId: "a")
        store.undoLastDeletion()
        #expect(store.bookshelf.shelves.map(\.name) == ["A", "B", "C", "D"])
        #expect(store.bookshelf.shelves[3].bookIds == [newId])
        #expect(store.bookshelf.shelves[0].bookIds.count == 3)   // Later, 1, 2
    }

    @Test func restoredShelfGetsANewNameIfItsNameWasTaken() {
        let store = store()
        store.deleteShelf("c")
        store.addShelf(named: "c")
        store.undoLastDeletion()
        #expect(store.bookshelf.shelves.map(\.name) == ["A", "B", "C 2", "c"])
    }

    @Test func undoesInReverseOrder() {
        let store = store()
        store.removeBook("1")
        store.deleteShelf("c")
        store.undoLastDeletion()
        #expect(store.bookshelf.shelves.count == 3)
        #expect(store.book(withId: "1") == nil)
        store.undoLastDeletion()
        #expect(store.book(withId: "1") != nil)
        #expect(store.undoLastDeletion() == nil)
    }

    @Test func keepsTheLastTenDeletions() {
        let store = store()
        for i in 0..<12 { store.addBook(title: "B\(i)", author: "", pageCount: nil, shelfId: "a") }
        let added = store.bookshelf.shelves[0].bookIds.prefix(12)
        for id in added { store.removeBook(id) }
        // Removed B11 first … B0 last. The two oldest (B11, B10) are dropped; B0 is undone first.
        #expect(store.undoStack.map(\.name) == (0..<10).reversed().map { "B\($0)" })
        for _ in 0..<LibraryStore.maxUndo { store.undoLastDeletion() }
        #expect(store.undoLastDeletion() == nil)
        #expect(store.books.count == 4 + LibraryStore.maxUndo)
    }

    @Test func savesTheRestoredBookAndShelf() async throws {
        let repo = InMemoryLibraryRepository(snapshot())
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        let before = try await repo.loadLibrary()
        store.removeBook("2")
        store.deleteShelf("c")
        await sync.waitUntilIdle()
        store.undoLastDeletion()
        store.undoLastDeletion()
        await sync.waitUntilIdle()
        let after = try await repo.loadLibrary()
        #expect(after.shelves == before.shelves)
        #expect(after.lists == before.lists)
        #expect(Set(after.books.map(\.id)) == Set(before.books.map(\.id)))
        #expect(after.metas.first { $0.bookId == "2" }?.notes == "Notes 2")
    }

    @Test func bookWithoutDetailsComesBackWithDefaultDetails() {
        let store = LibraryStore(books: [book("x")], metas: [],
                                 bookshelf: Bookshelf(id: "bs", name: "BS", shelves: [Shelf(id: "a", name: "A", bookIds: ["x"])],
                                                      appearance: .classic),
                                 coverLookup: NoCoverLookup())
        store.removeBook("x")
        store.undoLastDeletion()
        #expect(store.meta(for: "x")?.status == BookMeta.Status.want)
        #expect(store.bookshelf.shelves[0].bookIds == ["x"])
    }

    @Test func deletionsRememberWhenTheyHappened() {
        let store = store()
        let before = Date()
        store.removeBook("1")
        #expect(store.undoStack.last.map { $0.date >= before } == true)
    }
}

