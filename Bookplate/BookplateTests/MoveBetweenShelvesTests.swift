import Foundation
import Testing
@testable import Bookplate

@MainActor
struct MoveBetweenShelvesTests {
    private func store(_ shelves: [Shelf], sync: LibrarySync? = nil) -> LibraryStore {
        LibraryStore(books: [], metas: [],
                     bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic),
                     coverLookup: NoCoverLookup(), sync: sync)
    }

    private func shelves(lockB: Bool = false) -> [Shelf] {
        [Shelf(id: "a", name: "A", bookIds: ["1", "2", "3"]),
         Shelf(id: "b", name: "B", bookIds: ["4", "5"], isLocked: lockB),
         Shelf(id: "c", name: "C", bookIds: [])]
    }

    private func ids(_ store: LibraryStore) -> [[String]] { store.bookshelf.shelves.map(\.bookIds) }

    @Test func movesToASpotOnAnotherShelf() {
        let store = store(shelves())
        #expect(store.moveBook("2", from: "a", toShelf: "c", at: 0))
        #expect(ids(store) == [["1", "3"], ["4", "5"], ["2"]])
        #expect(store.moveBook("3", from: "a", toShelf: "c", at: 1))
        #expect(store.moveBook("1", from: "a", toShelf: "c", at: 1))
        #expect(ids(store) == [[], ["4", "5"], ["2", "1", "3"]])
    }

    @Test func clampsTheIndex() {
        let store = store(shelves())
        store.moveBook("1", from: "a", toShelf: "c", at: 99)
        store.moveBook("2", from: "a", toShelf: "c", at: -3)
        #expect(ids(store)[2] == ["2", "1"])
    }

    @Test func sameShelfIsAReorder() {
        let store = store(shelves())
        #expect(store.moveBook("1", from: "a", toShelf: "a", at: 2))
        #expect(ids(store)[0] == ["2", "3", "1"])
    }

    @Test func lockedShelvesRefuse() {
        let store = store(shelves(lockB: true))
        #expect(!store.moveBook("1", from: "a", toShelf: "b", at: 0))
        #expect(!store.moveBook("4", from: "b", toShelf: "a", at: 0))
        #expect(ids(store) == shelves().map(\.bookIds))
    }

    @Test func refusesBooksThatAreNotOnTheSourceOrUnknownShelves() {
        let store = store(shelves())
        #expect(!store.moveBook("4", from: "a", toShelf: "c", at: 0))
        #expect(!store.moveBook("1", from: "a", toShelf: "zzz", at: 0))
        #expect(ids(store) == shelves().map(\.bookIds))
    }

    @Test func aBookIsOnlyEverOnOneShelf() {
        let store = store([Shelf(id: "a", name: "A", bookIds: ["1", "2", "1"]),
                           Shelf(id: "b", name: "B", bookIds: ["2", "3"])])
        #expect(ids(store) == [["1", "2"], ["3"]])
        store.moveBook("3", from: "b", toShelf: "a", at: 0)
        store.moveBook("1", from: "a", toShelf: "b", at: 0)
        let all = store.bookshelf.shelves.flatMap(\.bookIds)
        #expect(all.count == Set(all).count)
    }

    @Test func deliberateDuplicatesAreSeparateBooks() throws {
        let store = store(shelves())
        let first = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: "c"))
        let second = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: "c"))
        #expect(first.id != second.id)
        #expect(ids(store)[2] == [second.id, first.id])
    }

    @Test func sampleDataFollowsTheOneCopyRule() throws {
        for bookshelf in try Bookshelf.sampleFromBundle() {
            let all = bookshelf.shelves.flatMap(\.bookIds)
            #expect(all.count == Set(all).count, "\(bookshelf.name)")
        }
        let shelves = try Shelf.sampleFromBundle().flatMap(\.bookIds)
        #expect(shelves.count == Set(shelves).count)
    }

    @Test func savesBothShelves() async throws {
        let books = (1...5).map { Book(id: "\($0)", title: "\($0)", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil) }
        let repo = InMemoryLibraryRepository(LibrarySnapshot(books: books, shelves: shelves()))
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        store.moveBook("5", from: "b", toShelf: "c", at: 0)
        await sync.waitUntilIdle()
        #expect(try await repo.loadLibrary().shelves.map(\.bookIds) == [["1", "2", "3"], ["4"], ["5"]])
    }

    @Test func loadingALibraryWithDuplicatesSavesTheFix() async throws {
        let books = (1...2).map { Book(id: "\($0)", title: "\($0)", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil) }
        let repo = InMemoryLibraryRepository(LibrarySnapshot(books: books, shelves: [
            Shelf(id: "a", name: "A", bookIds: ["1", "2"]), Shelf(id: "b", name: "B", bookIds: ["2"])]))
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        await sync.waitUntilIdle()
        #expect(repo.applied.isEmpty)       // nothing goes out until leftovers are queued
        store.saveOneCopyRepairs()
        await sync.waitUntilIdle()
        #expect(try await repo.loadLibrary().shelves.map(\.bookIds) == [["1", "2"], []])
    }
}
