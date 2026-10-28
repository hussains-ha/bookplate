import Foundation
import Testing
@testable import Bookplate

struct ShelfLockDecodingTests {
    @Test func missingIsLockedDefaultsToUnlocked() throws {
        let json = #"{"id":"s","name":"Shelf","bookIds":["a"]}"#
        let shelf = try JSONDecoder().decode(Shelf.self, from: Data(json.utf8))
        #expect(!shelf.isLocked)
    }

    @Test func decodesLockedShelf() throws {
        let json = #"{"id":"s","name":"Shelf","bookIds":[],"isLocked":true}"#
        #expect(try JSONDecoder().decode(Shelf.self, from: Data(json.utf8)).isLocked)
    }

    @Test func roundTripKeepsLock() throws {
        let shelf = Shelf(id: "s", name: "Shelf", bookIds: ["a"], isLocked: true)
        let decoded = try JSONDecoder().decode(Shelf.self, from: JSONEncoder().encode(shelf))
        #expect(decoded == shelf)
    }

    @Test func bundledSampleDataStillLoads() throws {
        #expect(try !Shelf.sampleFromBundle().isEmpty)
        #expect(try !Bookshelf.sampleFromBundle().isEmpty)
    }
}

@MainActor
struct ShelfLockStoreTests {
    private func store(locked: Set<String> = []) -> LibraryStore {
        let shelves = ["s1", "s2", "s3"].map {
            Shelf(id: $0, name: $0, bookIds: $0 == "s1" ? ["a", "b", "c"] : [], isLocked: locked.contains($0))
        }
        return LibraryStore(books: [], metas: [],
                            bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic))
    }

    @Test func setLockedLocksAndUnlocks() {
        let store = store()
        store.setLocked(true, onShelf: "s2")
        #expect(store.bookshelf.shelves[1].isLocked)
        store.setLocked(false, onShelf: "s2")
        #expect(!store.bookshelf.shelves[1].isLocked)
    }

    @Test func lockedShelfRejectsMovesUntilUnlocked() {
        let store = store(locked: ["s1"])
        #expect(!store.moveBook("a", onShelf: "s1", to: 2))
        #expect(store.bookshelf.shelves[0].bookIds == ["a", "b", "c"])
        store.setLocked(false, onShelf: "s1")
        #expect(store.moveBook("a", onShelf: "s1", to: 2))
        #expect(store.bookshelf.shelves[0].bookIds == ["b", "c", "a"])
    }

    @Test func defaultShelfSkipsLockedShelves() {
        #expect(store(locked: ["s1"]).defaultShelfId == "s2")
        #expect(store(locked: ["s1", "s2", "s3"]).defaultShelfId == nil)
    }

    @Test func addBookToLockedShelfFallsBackToFirstUnlocked() {
        let store = store(locked: ["s1", "s2"])
        let book = store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: "s2")
        #expect(book != nil)
        #expect(store.bookshelf.shelves[0].bookIds == ["a", "b", "c"])
        #expect(store.bookshelf.shelves[1].bookIds.isEmpty)
        #expect(store.bookshelf.shelves[2].bookIds == [book!.id])
    }

    @Test func addBookWithLockedFirstShelfAndNoTargetUsesFirstUnlocked() {
        let store = store(locked: ["s1"])
        let book = store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: nil)
        #expect(store.bookshelf.shelves[1].bookIds == [book!.id])
    }

    @Test func addBookToUnlockedShelfStillWorks() {
        let store = store(locked: ["s1"])
        let book = store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: "s3")
        #expect(store.bookshelf.shelves[2].bookIds == [book!.id])
    }

    @Test func addBookWhenEveryShelfIsLockedAddsNothing() {
        let store = store(locked: ["s1", "s2", "s3"])
        #expect(store.allShelvesLocked)
        #expect(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: "s1") == nil)
        #expect(store.books.isEmpty)
        #expect(store.bookshelf.shelves.allSatisfy { $0.bookIds.count == ($0.id == "s1" ? 3 : 0) })
    }
}
