import Foundation
import Testing
@testable import Bookplate

@MainActor
struct LibraryStoreCoverTests {
    final class MockCoverLookup: CoverLookup, @unchecked Sendable {
        var result: Result<CoverLookupResult?, Error>
        private(set) var calls = 0

        init(_ result: Result<CoverLookupResult?, Error>) { self.result = result }

        func lookup(title: String, author: String?, isbn: String?) async throws -> CoverLookupResult? {
            calls += 1
            return try result.get()
        }
    }

    private let cover = URL(string: "https://example.com/cover.jpg")!

    private func store(_ lookup: MockCoverLookup, books: [Book] = []) -> LibraryStore {
        LibraryStore(books: books, metas: [], bookshelf: Bookshelf(id: "b", name: "B", shelves: [], appearance: .classic),
                     coverLookup: lookup)
    }

    private func bareBook(id: String = "book-1", pageCount: Int? = nil) -> Book {
        Book(id: id, title: "Dune", authors: ["Frank Herbert"], pageCount: pageCount, coverUrl: nil, isbn13: nil)
    }

    @Test func fillsCoverAndMissingPageCount() async {
        let lookup = MockCoverLookup(.success(CoverLookupResult(coverURL: cover, pageCount: 688)))
        let store = store(lookup, books: [bareBook()])
        await store.fillCover(for: "book-1")
        #expect(store.books[0].coverUrl == cover)
        #expect(store.books[0].pageCount == 688)
        #expect(store.books[0].coverLookupAttempted == true)
    }

    @Test func keepsUserEnteredPageCountButStillFindsCover() async {
        let lookup = MockCoverLookup(.success(CoverLookupResult(coverURL: cover, pageCount: 688)))
        let store = store(lookup, books: [bareBook(pageCount: 500)])
        await store.fillCover(for: "book-1")
        #expect(store.books[0].coverUrl == cover)
        #expect(store.books[0].pageCount == 500)
    }

    @Test func noResultMarksAttemptedAndIsNotRetried() async {
        let lookup = MockCoverLookup(.success(nil))
        let store = store(lookup, books: [bareBook()])
        await store.backfillCovers()
        await store.backfillCovers()
        #expect(lookup.calls == 1)
        #expect(store.books[0].coverUrl == nil)
        #expect(store.books[0].coverLookupAttempted == true)
    }

    @Test func networkFailureIsRetriedLater() async {
        let lookup = MockCoverLookup(.failure(URLError(.notConnectedToInternet)))
        let store = store(lookup, books: [bareBook()])
        await store.backfillCovers()
        #expect(store.books[0].coverLookupAttempted != true)
        lookup.result = .success(CoverLookupResult(coverURL: cover, pageCount: nil))
        await store.backfillCovers()
        #expect(store.books[0].coverUrl == cover)
    }

    @Test func backfillSkipsBooksThatAlreadyHaveCovers() async {
        let lookup = MockCoverLookup(.success(CoverLookupResult(coverURL: cover, pageCount: nil)))
        var covered = bareBook(id: "book-2")
        covered.coverUrl = URL(string: "https://example.com/existing.jpg")
        let store = store(lookup, books: [bareBook(), covered])
        await store.backfillCovers()
        #expect(lookup.calls == 1)
        #expect(store.books[1].coverUrl?.absoluteString == "https://example.com/existing.jpg")
    }

    @Test func addBookAppearsImmediatelyAndGetsCoverLater() async {
        let lookup = MockCoverLookup(.success(CoverLookupResult(coverURL: cover, pageCount: 300)))
        let store = store(lookup)
        let book = store.addBook(title: "Dune", author: "Frank Herbert", pageCount: nil, shelfId: nil)
        #expect(store.books.first { $0.id == book.id }?.coverUrl == nil)
        for _ in 0..<100 where store.books.first(where: { $0.id == book.id })?.coverUrl == nil {
            await Task.yield()
        }
        #expect(store.books.first { $0.id == book.id }?.coverUrl == cover)
    }
}
