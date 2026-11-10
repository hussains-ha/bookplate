import Foundation
import Testing
@testable import Bookplate

struct ShelfSortTests {
    private static func book(_ id: String, _ title: String, by authors: [String]) -> Book {
        Book(id: id, title: title, authors: authors, isbn13: nil)
    }

    /// Saved order: 1, 2, 3, 4, 5.
    private let books = [
        Self.book("1", "dune", by: ["Frank Herbert"]),
        Self.book("2", "Émile", by: ["Jean-Jacques Rousseau"]),
        Self.book("3", "Book 10", by: ["Ann Austen"]),
        Self.book("4", "Book 9", by: []),
        Self.book("5", "Abc", by: ["Jane Austen", "Zed Zulu"]),
    ]
    private let ratings: [String: Int] = ["1": 3, "2": 5, "4": 3]

    private func ids(_ sort: ShelfSort) -> [String] {
        sort.apply(to: books) { ratings[$0.id] }.map(\.id)
    }

    @Test func customKeepsSavedOrder() {
        #expect(ids(.custom) == ["1", "2", "3", "4", "5"])
    }

    @Test func titleSortsNaturallyIgnoringCaseAndAccents() {
        // "Book 9" before "Book 10"; "dune" between B and É.
        #expect(ids(.title) == ["5", "4", "3", "1", "2"])
    }

    @Test func authorUsesFirstAuthorsLastNameThenFirstName() {
        // Austen Ann, Austen Jane, Herbert, Rousseau, then the book with no author.
        #expect(ids(.author) == ["3", "5", "1", "2", "4"])
    }

    @Test func authorKeyPutsLastNameFirst() {
        #expect(ShelfSort.authorKey(books[0]) == "Herbert Frank")
        #expect(ShelfSort.authorKey(Self.book("x", "X", by: ["Plato"])) == "Plato")
        #expect(ShelfSort.authorKey(Self.book("x", "X", by: ["  "])) == nil)
    }

    @Test func ratingIsHighestFirstWithUnratedLastAndTiesInSavedOrder() {
        #expect(ids(.rating) == ["2", "1", "4", "3", "5"])
    }

    @Test func sortingDoesNotChangeTheInput() {
        _ = ShelfSort.title.apply(to: books) { _ in nil }
        #expect(books.map(\.id) == ["1", "2", "3", "4", "5"])
    }
}
