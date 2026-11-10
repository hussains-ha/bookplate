import Foundation
import Testing
@testable import Bookplate

@MainActor
struct SmartShelfTests {
    private func book(_ id: String) -> Book { Book(id: id, title: "Book \(id)", authors: ["A"], isbn13: nil) }

    private func meta(_ id: String, _ status: String, rating: Int? = nil) -> BookMeta {
        BookMeta(bookId: id, status: status, rating: rating, notes: nil, notePhotos: [], tags: [],
                 customCover: nil, addedDate: Date(timeIntervalSince1970: 0))
    }

    private func store(_ metas: [BookMeta]) -> LibraryStore {
        LibraryStore(
            books: ["1", "2", "3", "4", "5"].map(book),
            metas: metas,
            bookshelf: Bookshelf(id: "b", name: "B", shelves: [
                Shelf(id: "x", name: "X", bookIds: ["3", "1"]),
                Shelf(id: "y", name: "Y", bookIds: ["4", "2", "5"]),
            ], appearance: .classic),
            coverLookup: NoCoverLookup())
    }

    private func summary(_ store: LibraryStore) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: store.smartShelves().map { ($0.shelf.name, $0.books.map(\.id)) })
    }

    @Test func gathersBooksByStatusAndFiveStarsInBookcaseOrder() {
        let store = store([meta("1", BookMeta.Status.reading),
                           meta("2", BookMeta.Status.want, rating: 5),
                           meta("3", BookMeta.Status.reading, rating: 5),
                           meta("4", BookMeta.Status.read, rating: 4),
                           meta("5", BookMeta.Status.want)])
        #expect(store.smartShelves().map(\.shelf.name) == ["Currently Reading", "Want to Read", "Favorites"])
        #expect(summary(store) == ["Currently Reading": ["3", "1"], "Want to Read": ["2", "5"], "Favorites": ["3", "2"]])
    }

    @Test func emptySmartShelvesAreHidden() {
        let store = store([meta("1", BookMeta.Status.read, rating: 4)])
        #expect(store.smartShelves().isEmpty)
        store.setStatus(BookMeta.Status.want, for: "1")
        #expect(store.smartShelves().map(\.shelf.name) == ["Want to Read"])
    }

    @Test func updatesWhenStatusOrRatingChanges() {
        let store = store([meta("1", BookMeta.Status.reading), meta("2", BookMeta.Status.read, rating: 5)])
        store.setStatus(BookMeta.Status.read, for: "1")
        #expect(summary(store)["Currently Reading"] == nil)
        store.setRating(5, for: "1")
        #expect(summary(store)["Favorites"] == ["1", "2"])
        store.setRating(4, for: "2")
        #expect(summary(store)["Favorites"] == ["1"])
    }

    @Test func removedBooksLeaveSmartShelves() {
        let store = store([meta("1", BookMeta.Status.reading)])
        store.removeBook("1")
        #expect(store.smartShelves().isEmpty)
    }

    @Test func smartShelfIdsAreRecognisedAndNeverSaved() {
        let store = store([meta("1", BookMeta.Status.reading)])
        #expect(store.smartShelves().allSatisfy { SmartShelf.isSmart($0.shelf.id) })
        #expect(!store.bookshelf.shelves.contains { SmartShelf.isSmart($0.id) })
        #expect(!SmartShelf.isSmart("x"))
    }
}
