import Foundation
import Testing
@testable import Bookplate

@MainActor
struct EmptyStateTests {
    private func book(_ id: String, _ title: String, by author: String) -> Book {
        Book(id: id, title: title, authors: [author], isbn13: nil)
    }

    private func store(books: [Book], shelves: [Shelf]) -> LibraryStore {
        LibraryStore(books: books, metas: [],
                     bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic),
                     coverLookup: NoCoverLookup())
    }

    private var sample: LibraryStore {
        store(books: [book("1", "Dune", by: "Frank Herbert"),
                      book("2", "Emma", by: "Jane Austen"),
                      book("3", "Café Society", by: "Ann Smith")],
              shelves: [Shelf(id: "a", name: "Sci-fi", bookIds: ["1"]),
                        Shelf(id: "b", name: "Empty", bookIds: []),
                        Shelf(id: "c", name: "Classics", bookIds: ["2", "3"])])
    }

    private func names(_ shelves: [LibraryStore.VisibleShelf]) -> [String] { shelves.map(\.shelf.name) }

    @Test(arguments: ["", "   ", "\n\t"])
    func noSearchShowsEveryShelfIncludingEmptyOnes(_ query: String) {
        let visible = sample.visibleShelves(matching: query)
        #expect(names(visible) == ["Sci-fi", "Empty", "Classics"])
        #expect(visible.map { $0.books.map(\.id) } == [["1"], [], ["2", "3"]])
        #expect(!LibraryStore.isSearching(query))
    }

    @Test func searchHidesShelvesWithoutMatches() {
        let visible = sample.visibleShelves(matching: "emma")
        #expect(names(visible) == ["Classics"])
        #expect(visible.first?.books.map(\.id) == ["2"])
    }

    @Test func searchMatchesAuthorsAndKeepsShelfOrder() {
        // "an" is in "Frank Herbert", "Jane Austen" and "Ann Smith".
        let visible = sample.visibleShelves(matching: "an")
        #expect(names(visible) == ["Sci-fi", "Classics"])
        #expect(visible.last?.books.map(\.id) == ["2", "3"])
    }

    @Test(arguments: ["CAFE", "  café ", "Cafe"])
    func searchIgnoresCaseAccentsAndSurroundingSpaces(_ query: String) {
        let visible = sample.visibleShelves(matching: query)
        #expect(names(visible) == ["Classics"])
        #expect(visible.first?.books.map(\.id) == ["3"])
        #expect(LibraryStore.isSearching(query))
    }

    @Test func searchWithNoMatchesShowsNoShelves() {
        #expect(sample.visibleShelves(matching: "zzz").isEmpty)
    }

    @Test func libraryIsEmptyOnlyWithNoBooks() {
        let empty = store(books: [], shelves: [Shelf(id: "a", name: "A", bookIds: [])])
        #expect(empty.isLibraryEmpty)
        #expect(!sample.isLibraryEmpty)
    }

    @Test func removingTheLastBookEmptiesTheLibrary() {
        let store = store(books: [book("1", "Dune", by: "Frank Herbert")],
                          shelves: [Shelf(id: "a", name: "A", bookIds: ["1"])])
        store.removeBook("1")
        #expect(store.isLibraryEmpty)
        #expect(names(store.visibleShelves()) == ["A"])
    }
}
