import Foundation
import Supabase
import Testing
@testable import Bookplate

struct BookRowTests {
    @Test func roundTripsEveryField() {
        var book = Book.mock
        book.coverLookupAttempted = true
        #expect(BookRow(book).book == book)
    }

    @Test func roundTripsBookWithoutOptionalFields() {
        let book = Book(id: "book-x", title: "X", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil)
        #expect(BookRow(book).book == book)
    }

    @Test func encodesSnakeCaseColumnsWithoutUserId() throws {
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BookRow(.mock))) as? [String: Any]
        let keys = Set(json?.keys.map { $0 } ?? [])
        #expect(keys.isSuperset(of: ["id", "title", "authors", "page_count", "cover_url", "isbn13"]))
        #expect(!keys.contains("user_id"))
        #expect(!keys.contains("pageCount"))
    }

    @Test func encodesNilColumnsSoClearedValuesAreSaved() throws {
        let book = Book(id: "book-x", title: "X", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(BookRow(book))) as? [String: Any]
        for column in ["page_count", "cover_url", "isbn13", "cover_lookup_attempted"] {
            #expect(json?[column] is NSNull, "\(column) should be sent as null")
        }
    }

    @Test(arguments: [0, -3])
    func nonPositivePageCountsAreSavedAsUnknown(pages: Int) {
        let book = Book(id: "book-x", title: "X", authors: [], pageCount: pages, coverUrl: nil, isbn13: nil)
        #expect(BookRow(book).pageCount == nil)
    }

    @Test func decodesARowFromTheDatabase() throws {
        let json = """
        {"user_id": "5f0c3f1e-0000-4000-8000-000000000000", "id": "book-dune", "title": "Dune",
         "authors": ["Frank Herbert"], "page_count": 688, "cover_url": "https://example.com/d.jpg",
         "isbn13": null, "cover_lookup_attempted": null, "created_at": "2026-11-09T00:00:00Z"}
        """
        let book = try JSONDecoder().decode(BookRow.self, from: Data(json.utf8)).book
        #expect(book.id == "book-dune")
        #expect(book.pageCount == 688)
        #expect(book.coverUrl == URL(string: "https://example.com/d.jpg"))
        #expect(book.isbn13 == nil)
    }
}

struct BookServiceErrorTests {
    @Test func mapsErrors() {
        #expect(BookService.failure(from: URLError(.notConnectedToInternet)) == .network)
        #expect(BookService.failure(from: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))) == .decoding)
        #expect(BookService.failure(from: PostgrestError(code: "PGRST301", message: "JWT expired")) == .notSignedIn)
        #expect(BookService.failure(from: PostgrestError(code: "23505", message: "duplicate key")) == .server("duplicate key"))
    }
}

struct InMemoryBookRepositoryTests {
    @Test func addsUpdatesAndDeletes() async throws {
        let repo = InMemoryBookRepository()
        try await repo.addBook(.mock)
        var updated = Book.mock
        updated.pageCount = 1
        try await repo.updateBook(updated)
        #expect(try await repo.fetchBooks() == [updated])
        try await repo.deleteBook(id: Book.mock.id)
        #expect(try await repo.fetchBooks().isEmpty)
    }

    @Test func rejectsDuplicateIds() async throws {
        let repo = InMemoryBookRepository(books: [.mock])
        await #expect(throws: BookServiceError.self) { try await repo.addBook(.mock) }
    }
}
