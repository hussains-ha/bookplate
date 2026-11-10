import Foundation
import Testing
@testable import Bookplate

@MainActor
struct DeleteShelfTests {
    private func store(_ shelves: [Shelf]) -> LibraryStore {
        LibraryStore(books: [], metas: [],
                     bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic),
                     coverLookup: NoCoverLookup())
    }

    private func shelf(_ id: String, _ books: [String] = [], locked: Bool = false) -> Shelf {
        Shelf(id: id, name: id.uppercased(), bookIds: books, isLocked: locked)
    }

    @Test func movesBooksToTheFirstRemainingShelf() {
        let store = store([shelf("a", ["1"]), shelf("b", ["2", "3"]), shelf("c", ["4"])])
        #expect(store.shelfDeletion("b") == .allowed(moveTo: shelf("a", ["1"])))
        #expect(store.deleteShelf("b"))
        #expect(store.bookshelf.shelves.map(\.id) == ["a", "c"])
        #expect(store.bookshelf.shelves[0].bookIds == ["1", "2", "3"])
    }

    @Test func deletingTheFirstShelfMovesBooksToTheNextOne() {
        let store = store([shelf("a", ["1"]), shelf("b", ["2"])])
        #expect(store.deleteShelf("a"))
        #expect(store.bookshelf.shelves == [shelf("b", ["2", "1"])])
    }

    @Test func skipsLockedShelvesWhenMovingBooks() {
        let store = store([shelf("a", ["1"], locked: true), shelf("b", ["2"]), shelf("c", ["3"])])
        #expect(store.deleteShelf("c"))
        #expect(store.bookshelf.shelves[0].bookIds == ["1"])
        #expect(store.bookshelf.shelves[1].bookIds == ["2", "3"])
    }

    @Test func keepsAtLeastOneShelf() {
        let store = store([shelf("a", ["1"])])
        #expect(store.shelfDeletion("a") == .lastShelf)
        #expect(!store.deleteShelf("a"))
        #expect(store.bookshelf.shelves.count == 1)
    }

    @Test func refusesWhenBooksHaveNowhereToGo() {
        let store = store([shelf("a", locked: true), shelf("b", ["1"])])
        #expect(store.shelfDeletion("b") == .noShelfForBooks)
        #expect(!store.deleteShelf("b"))
        #expect(store.bookshelf.shelves.count == 2)
    }

    @Test func emptyShelvesAndLockedShelvesCanBeDeleted() {
        let store = store([shelf("a", locked: true), shelf("b"), shelf("c", ["1"], locked: true)])
        #expect(store.shelfDeletion("b") == .allowed(moveTo: nil))
        #expect(store.deleteShelf("b"))
        #expect(store.shelfDeletion("c") == .noShelfForBooks)
        #expect(store.deleteShelf("a"))
        #expect(store.bookshelf.shelves.map(\.id) == ["c"])
    }

    @Test func unknownShelf() {
        let store = store([shelf("a"), shelf("b")])
        #expect(store.shelfDeletion("x") == nil)
        #expect(!store.deleteShelf("x"))
    }

    @Test func savesMovedBooksDeleteAndNewPositions() async throws {
        let books = ["1", "2", "3"].map { Book(id: $0, title: $0, authors: [], pageCount: nil, coverUrl: nil, isbn13: nil) }
        let snapshot = LibrarySnapshot(books: books,
                                       shelves: [shelf("a", ["1"]), shelf("b", ["2", "3"]), shelf("c")])
        let repo = InMemoryLibraryRepository(snapshot)
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        #expect(store.deleteShelf("b"))
        await sync.waitUntilIdle()
        #expect(repo.applied.first == .setShelfBooks(shelfId: "a", bookIds: ["1", "2", "3"]))
        #expect(repo.applied.contains(.deleteShelf(id: "b")))
        let reloaded = try await repo.loadLibrary()
        #expect(reloaded.shelves.map(\.id) == ["a", "c"])
        #expect(reloaded.shelves[0].bookIds == ["1", "2", "3"])
        #expect(reloaded.books.count == 3)
    }
}
