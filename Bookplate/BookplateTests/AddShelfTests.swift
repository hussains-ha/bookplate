import Foundation
import Testing
@testable import Bookplate

@MainActor
struct AddShelfTests {
    private func store(_ names: [String] = ["Fiction"], locked: Bool = false) -> LibraryStore {
        let shelves = names.enumerated().map { Shelf(id: "s\($0)", name: $1, bookIds: ["b\($0)"], isLocked: locked) }
        return LibraryStore(books: [], metas: [],
                            bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic),
                            coverLookup: NoCoverLookup())
    }

    @Test func addsEmptyUnlockedShelfAtTheBottom() throws {
        let store = store(["Fiction", "Memoir"])
        let shelf = try #require(store.addShelf(named: "  Favorites \n"))
        #expect(store.bookshelf.shelves.map(\.name) == ["Fiction", "Memoir", "Favorites"])
        #expect(store.bookshelf.shelves.last == shelf)
        #expect(shelf.bookIds.isEmpty)
        #expect(!shelf.isLocked)
        #expect(shelf.id.hasPrefix("shelf-"))
    }

    @Test(arguments: ["", "   ", "\n\t "])
    func rejectsBlankNames(_ name: String) {
        let store = store()
        #expect(store.shelfNameProblem(name) == .blank)
        #expect(store.addShelf(named: name) == nil)
        #expect(store.bookshelf.shelves.count == 1)
    }

    @Test(arguments: ["Fiction", "fiction", "  FICTION  "])
    func rejectsDuplicateNamesIgnoringCaseAndSpaces(_ name: String) {
        let store = store()
        #expect(store.shelfNameProblem(name) == .duplicate)
        #expect(store.addShelf(named: name) == nil)
        #expect(store.bookshelf.shelves.count == 1)
    }

    @Test func duplicateCheckIncludesShelvesJustAdded() {
        let store = store()
        store.addShelf(named: "Favorites")
        #expect(store.addShelf(named: "favorites") == nil)
    }

    @Test func capsNameLength() {
        let store = store()
        let max = String(repeating: "a", count: LibraryStore.maxShelfNameLength)
        #expect(store.shelfNameProblem(max + "a") == .tooLong)
        #expect(store.addShelf(named: max + "a") == nil)
        #expect(store.addShelf(named: max)?.name == max)
    }

    @Test func idsAreUnique() {
        let store = store([])
        for i in 0..<50 { store.addShelf(named: "Shelf \(i)") }
        #expect(Set(store.bookshelf.shelves.map(\.id)).count == 50)
    }

    @Test func worksWithNoShelvesAndWhenAllAreLocked() {
        #expect(store([]).addShelf(named: "First") != nil)
        let locked = store(locked: true)
        #expect(locked.allShelvesLocked)
        locked.addShelf(named: "Open")
        #expect(!locked.allShelvesLocked)
    }

    @Test func newShelfCanTakeBooksFromAddBook() throws {
        let store = store()
        let shelf = try #require(store.addShelf(named: "Favorites"))
        let book = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: shelf.id))
        #expect(store.bookshelf.shelves.last?.bookIds == [book.id])
    }

    @Test func savesTheShelfToSupabase() async throws {
        let repo = InMemoryLibraryRepository(LibrarySnapshot(shelves: [Shelf(id: "s0", name: "Fiction", bookIds: [])]))
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        let shelf = try #require(store.addShelf(named: "Favorites"))
        await sync.waitUntilIdle()
        #expect(repo.applied == [.saveShelf(shelf, position: 1)])
        #expect(repo.snapshot.shelves.map(\.name) == ["Fiction", "Favorites"])
    }
}
