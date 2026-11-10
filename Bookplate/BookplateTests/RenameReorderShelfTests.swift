import Foundation
import Testing
@testable import Bookplate

@MainActor
struct RenameReorderShelfTests {
    private func store(_ names: [String] = ["A", "B", "C", "D"], locked: Bool = false,
                       sync: LibrarySync? = nil) -> LibraryStore {
        let shelves = names.map { Shelf(id: "s-\($0)", name: $0, bookIds: ["b-\($0)"], isLocked: locked) }
        return LibraryStore(books: [], metas: [],
                            bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic),
                            coverLookup: NoCoverLookup(), sync: sync)
    }

    private func names(_ store: LibraryStore) -> [String] { store.bookshelf.shelves.map(\.name) }

    // MARK: Rename

    @Test func renamesTrimmedAndKeepsBooks() {
        let store = store()
        #expect(store.renameShelf("s-B", to: "  Favorites ") == nil)
        #expect(names(store) == ["A", "Favorites", "C", "D"])
        #expect(store.bookshelf.shelves[1].bookIds == ["b-B"])
    }

    @Test(arguments: ["", "  ", "\n"])
    func rejectsBlankNames(_ name: String) {
        let store = store()
        #expect(store.renameShelf("s-B", to: name) == .blank)
        #expect(names(store) == ["A", "B", "C", "D"])
    }

    @Test func rejectsAnotherShelfsNameButAllowsItsOwnInNewCase() {
        let store = store()
        #expect(store.renameShelf("s-B", to: "c") == .duplicate)
        #expect(store.renameShelf("s-B", to: "b") == nil)
        #expect(names(store) == ["A", "b", "C", "D"])
    }

    @Test func rejectsLongNames() {
        let store = store()
        #expect(store.renameShelf("s-B", to: String(repeating: "x", count: 41)) == .tooLong)
    }

    @Test func renamesLockedShelves() {
        let store = store(locked: true)
        #expect(store.renameShelf("s-A", to: "Keep") == nil)
        #expect(store.bookshelf.shelves[0].name == "Keep")
        #expect(store.bookshelf.shelves[0].isLocked)
    }

    // MARK: Reorder

    @Test func movesUpAndDown() {
        let store = store()
        store.moveShelf("s-C", to: 1)
        #expect(names(store) == ["A", "C", "B", "D"])
        store.moveShelf("s-A", to: 3)
        #expect(names(store) == ["C", "B", "D", "A"])
    }

    @Test func clampsAndIgnoresUnknownShelves() {
        let store = store()
        store.moveShelf("s-B", to: -5)
        #expect(names(store) == ["B", "A", "C", "D"])
        store.moveShelf("s-B", to: 99)
        #expect(names(store) == ["A", "C", "D", "B"])
        store.moveShelf("nope", to: 0)
        #expect(names(store) == ["A", "C", "D", "B"])
    }

    @Test func movesLockedShelves() {
        let store = store(locked: true)
        store.moveShelf("s-D", to: 0)
        #expect(names(store) == ["D", "A", "B", "C"])
    }

    // MARK: Saving

    @Test func savesRenameAndNewPositions() async throws {
        let shelves = ["A", "B", "C", "D"].map { Shelf(id: "s-\($0)", name: $0, bookIds: []) }
        let repo = InMemoryLibraryRepository(LibrarySnapshot(shelves: shelves))
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        store.renameShelf("s-A", to: "First")
        store.renameShelf("s-B", to: "B")          // unchanged: not saved
        store.moveShelf("s-D", to: 1)
        await sync.waitUntilIdle()

        #expect(repo.applied.count == 4)           // the rename + shelves at positions 1...3
        #expect(repo.snapshot.shelves.map(\.name) == ["First", "D", "B", "C"])
        // What a reload would show.
        #expect(try await repo.loadLibrary().shelves.map(\.name) == store.bookshelf.shelves.map(\.name))
    }
}
