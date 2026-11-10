import Foundation
import Testing
@testable import Bookplate

@MainActor
struct FilterMenuTests {
    private func book(_ id: String, _ title: String, by author: String) -> Book {
        Book(id: id, title: title, authors: [author], isbn13: nil)
    }

    private func meta(_ id: String, _ status: String, rating: Int? = nil, tags: [String] = []) -> BookMeta {
        BookMeta(bookId: id, status: status, rating: rating, notes: nil, notePhotos: [], tags: tags,
                 customCover: nil, addedDate: Date(timeIntervalSince1970: 0))
    }

    /// Sci-fi: Dune (reading, 5★, #space), Foundation (want, #space #Classic)
    /// Classics: Emma (read, 5★, #classic), Persuasion (read, 3★)
    /// Empty shelf; plus Orphan, a book with no meta.
    private func store() -> LibraryStore {
        LibraryStore(
            books: [book("1", "Dune", by: "Frank Herbert"), book("2", "Foundation", by: "Isaac Asimov"),
                    book("3", "Emma", by: "Jane Austen"), book("4", "Persuasion", by: "Jane Austen"),
                    book("5", "Orphan", by: "Nobody")],
            metas: [meta("1", BookMeta.Status.reading, rating: 5, tags: ["space"]),
                    meta("2", BookMeta.Status.want, tags: ["space", "Classic"]),
                    meta("3", BookMeta.Status.read, rating: 5, tags: ["classic"]),
                    meta("4", BookMeta.Status.read, rating: 3)],
            bookshelf: Bookshelf(id: "b", name: "B", shelves: [
                Shelf(id: "a", name: "Sci-fi", bookIds: ["1", "2"]),
                Shelf(id: "c", name: "Classics", bookIds: ["3", "4", "5"]),
                Shelf(id: "e", name: "Empty", bookIds: []),
            ], appearance: .classic),
            coverLookup: NoCoverLookup())
    }

    private func ids(_ shelves: [LibraryStore.VisibleShelf]) -> [[String]] { shelves.map { $0.books.map(\.id) } }

    // MARK: Counts

    @Test func countsEachFilter() {
        let store = store()
        #expect(store.count(for: .all) == 5)
        #expect(store.count(for: .status(BookMeta.Status.reading)) == 1)
        #expect(store.count(for: .status(BookMeta.Status.want)) == 1)
        #expect(store.count(for: .status(BookMeta.Status.read)) == 2)
        #expect(store.count(for: .favorites) == 2)
        #expect(store.count(for: .tag("space")) == 2)
        #expect(store.count(for: .tag("CLASSIC")) == 2)
    }

    @Test func tagsAreListedOnceIgnoringCaseAndSorted() {
        #expect(store().allTags == ["Classic", "space"])
    }

    @Test func tagsOfRemovedBooksAreNotListed() {
        let store = store()
        store.removeBook("1")
        store.removeBook("2")
        #expect(store.allTags == ["classic"])
    }

    // MARK: Matching

    @Test func filterAppliesToEveryShelfAndHidesShelvesWithoutMatches() {
        let store = store()
        let visible = store.visibleShelves(filter: .favorites)
        #expect(visible.map(\.shelf.id) == ["a", "c"])
        #expect(ids(visible) == [["1"], ["3"]])
        #expect(ids(store.visibleShelves(filter: .status(BookMeta.Status.read))) == [["3", "4"]])
        #expect(ids(store.visibleShelves(filter: .tag("classic"))) == [["2"], ["3"]])
    }

    @Test func allShowsEveryShelfIncludingEmpty() {
        #expect(store().visibleShelves(filter: .all).map(\.shelf.id) == ["a", "c", "e"])
    }

    @Test func searchMatchesTags() {
        #expect(ids(store().visibleShelves(matching: "SPA")) == [["1", "2"]])
    }

    @Test func searchMatchingAShelfNameShowsAllItsBooks() {
        #expect(ids(store().visibleShelves(matching: "classics")) == [["3", "4", "5"]])
        // "sci" matches the shelf name, so every Sci-fi book shows, even ones whose title doesn't match.
        #expect(ids(store().visibleShelves(matching: "sci")) == [["1", "2"]])
    }

    @Test func searchStillMatchesTitlesAndAuthors() {
        #expect(ids(store().visibleShelves(matching: "austen")) == [["3", "4"]])
        #expect(ids(store().visibleShelves(matching: "dune")) == [["1"]])
    }

    @Test func searchAndFilterCombine() {
        let store = store()
        #expect(ids(store.visibleShelves(matching: "classics", filter: .favorites)) == [["3"]])
        #expect(ids(store.visibleShelves(matching: "austen", filter: .status(BookMeta.Status.want))).isEmpty)
    }

    @Test func booksWithoutDetailsOnlyMatchAll() {
        let store = store()
        for filter in [LibraryFilter.status(BookMeta.Status.want), .favorites, .tag("space")] {
            #expect(!store.visibleShelves(filter: filter).flatMap(\.books).contains { $0.id == "5" })
        }
    }

    @Test func filterUpdatesWhenDetailsChange() {
        let store = store()
        store.setRating(5, for: "4")
        #expect(store.count(for: .favorites) == 3)
        store.setStatus(BookMeta.Status.reading, for: "2")
        #expect(ids(store.visibleShelves(filter: .status(BookMeta.Status.reading))) == [["1", "2"]])
    }

    // MARK: Tag reset

    @Test func missingTagResetsToAll() {
        let store = store()
        store.removeTag("space", from: "1")
        #expect(store.resolved(.tag("space")) == .tag("space"))
        store.removeTag("space", from: "2")
        #expect(store.resolved(.tag("space")) == .all)
    }

    @Test func otherFiltersAreKeptEvenWhenEmpty() {
        let store = store()
        #expect(store.resolved(.tag("Space")) == .tag("Space"))
        #expect(store.resolved(.favorites) == .favorites)
        #expect(store.resolved(.status("unknown")) == .status("unknown"))
        #expect(store.resolved(.all) == .all)
    }
}
