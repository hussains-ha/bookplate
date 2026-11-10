import Foundation
import Testing
@testable import Bookplate

@MainActor
struct JumpToShelfTests {
    private func store(_ shelves: [Shelf], books: [String] = ["1", "2", "3"]) -> LibraryStore {
        LibraryStore(books: books.map { Book(id: $0, title: "B\($0)", authors: [], isbn13: nil) }, metas: [],
                     bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic),
                     coverLookup: NoCoverLookup())
    }

    @Test func listsEveryShelfInOrderWithCounts() {
        let store = store([Shelf(id: "a", name: "A", bookIds: ["1", "2"]),
                           Shelf(id: "e", name: "Empty", bookIds: []),
                           Shelf(id: "c", name: "C", bookIds: ["3"])])
        #expect(store.shelfJumps == [.init(id: "a", name: "A", count: 2),
                                     .init(id: "e", name: "Empty", count: 0),
                                     .init(id: "c", name: "C", count: 1)])
    }

    @Test func hiddenWithOneShelfOrNone() {
        #expect(store([Shelf(id: "a", name: "A", bookIds: ["1"])]).shelfJumps.isEmpty)
        #expect(store([]).shelfJumps.isEmpty)
    }

    @Test func countsOnlyBooksThatExistAndFollowsChanges() {
        let store = store([Shelf(id: "a", name: "A", bookIds: ["1", "missing"]),
                           Shelf(id: "c", name: "C", bookIds: ["2"])])
        #expect(store.shelfJumps.map(\.count) == [1, 1])
        store.renameShelf("c", to: "Renamed")
        store.moveShelf("c", to: 0)
        #expect(store.shelfJumps.map(\.name) == ["Renamed", "A"])
    }
}
