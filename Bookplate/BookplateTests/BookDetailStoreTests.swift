import Foundation
import Testing
@testable import Bookplate

@MainActor
struct BookDetailStoreTests {
    private func store() -> LibraryStore {
        let books = [
            Book(id: "a", title: "A", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil),
            Book(id: "b", title: "B", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil),
        ]
        let metas = books.map {
            BookMeta(bookId: $0.id, status: BookMeta.Status.want, rating: nil, notes: nil, notePhotos: [], tags: [],
                     customCover: nil, addedDate: .now, startedDate: nil, finishedDate: nil)
        }
        let shelves = [Shelf(id: "s1", name: "One", bookIds: ["a", "b"]), Shelf(id: "s2", name: "Two", bookIds: ["a"])]
        let store = LibraryStore(books: books, metas: metas,
                                 bookshelf: Bookshelf(id: "bs", name: "BS", shelves: shelves, appearance: .classic))
        store.addList(BookList(id: "l1", name: "List", bookIds: []))
        return store
    }

    @Test func setsStatus() {
        let store = store()
        store.setStatus(BookMeta.Status.read, for: "a")
        #expect(store.meta(for: "a")?.status == BookMeta.Status.read)
        #expect(store.meta(for: "b")?.status == BookMeta.Status.want)
    }

    @Test func ratingIsLimitedToOneThroughFiveOrCleared() {
        let store = store()
        store.setRating(4, for: "a")
        #expect(store.meta(for: "a")?.rating == 4)
        store.setRating(0, for: "a")
        store.setRating(6, for: "a")
        store.setRating(-1, for: "a")
        #expect(store.meta(for: "a")?.rating == 4)
        store.setRating(nil, for: "a")
        #expect(store.meta(for: "a")?.rating == nil)
    }

    @Test func emptyNotesBecomeNil() {
        let store = store()
        store.setNotes("Chapter 4", for: "a")
        #expect(store.meta(for: "a")?.notes == "Chapter 4")
        store.setNotes("", for: "a")
        #expect(store.meta(for: "a")?.notes == nil)
    }

    @Test func tagsAreTrimmedAndNotDuplicated() {
        let store = store()
        store.addTag("  habits ", to: "a")
        store.addTag("Habits", to: "a")
        store.addTag("   ", to: "a")
        #expect(store.meta(for: "a")?.tags == ["habits"])
        store.removeTag("habits", from: "a")
        #expect(store.meta(for: "a")?.tags == [])
    }

    @Test func photosAndCustomCover() {
        let store = store()
        let photo = URL(string: "file:///photo.jpg")!
        store.addNotePhoto(photo, to: "a")
        #expect(store.meta(for: "a")?.notePhotos == [photo])
        store.removeNotePhoto(photo, from: "a")
        #expect(store.meta(for: "a")?.notePhotos == [])

        store.setCustomCover(photo, for: "a")
        #expect(store.meta(for: "a")?.customCover == photo)
        store.setCustomCover(nil, for: "a")
        #expect(store.meta(for: "a")?.customCover == nil)
    }

    @Test func listMembershipAddsAndRemovesOnce() {
        let store = store()
        store.setBook("a", inList: "l1", to: true)
        store.setBook("a", inList: "l1", to: true)
        #expect(store.lists(containing: "a").map(\.id) == ["l1"])
        #expect(store.lists[0].bookIds == ["a"])
        store.setBook("a", inList: "l1", to: false)
        #expect(store.lists(containing: "a").isEmpty)
    }

    @Test func listChangesIgnoreUnknownBooksAndLists() {
        let store = store()
        store.setBook("zzz", inList: "l1", to: true)
        store.setBook("a", inList: "nope", to: true)
        #expect(store.lists[0].bookIds.isEmpty)
    }

    @Test func shelvesContainingABook() {
        let store = store()
        #expect(store.shelves(containing: "a").map(\.id) == ["s1", "s2"])
        #expect(store.shelves(containing: "b").map(\.id) == ["s1"])
    }

    @Test func removeBookClearsEverywhere() {
        let store = store()
        store.setBook("a", inList: "l1", to: true)
        store.removeBook("a")
        #expect(store.book(withId: "a") == nil)
        #expect(store.meta(for: "a") == nil)
        #expect(store.bookshelf.shelves.allSatisfy { !$0.bookIds.contains("a") })
        #expect(store.lists.allSatisfy { !$0.bookIds.contains("a") })
        #expect(store.book(withId: "b") != nil)
        #expect(store.bookshelf.shelves[0].bookIds == ["b"])
    }
}
