import Foundation
import Testing
@testable import Bookplate

struct BookCoverTests {
    private let official = URL(string: "https://covers.openlibrary.org/b/isbn/1-L.jpg?default=false")
    private let custom = URL(string: "https://example.com/custom.jpg")

    private func book(coverUrl: URL?) -> Book {
        Book(id: "b", title: "T", authors: ["A"], pageCount: nil, coverUrl: coverUrl, isbn13: nil)
    }

    private func meta(customCover: URL?) -> BookMeta {
        BookMeta(bookId: "b", status: BookMeta.Status.want, rating: nil, notes: nil, notePhotos: [], tags: [],
                 customCover: customCover, addedDate: .now, startedDate: nil, finishedDate: nil)
    }

    @Test func customCoverOnly() {
        #expect(book(coverUrl: nil).displayCoverURL(meta: meta(customCover: custom)) == custom)
    }

    @Test func officialCoverOnly() {
        #expect(book(coverUrl: official).displayCoverURL(meta: meta(customCover: nil)) == official)
        #expect(book(coverUrl: official).displayCoverURL(meta: nil) == official)
    }

    @Test func customWinsOverOfficial() {
        #expect(book(coverUrl: official).displayCoverURL(meta: meta(customCover: custom)) == custom)
    }

    @Test func neitherFallsBackToGenerated() {
        #expect(book(coverUrl: nil).displayCoverURL(meta: meta(customCover: nil)) == nil)
        #expect(book(coverUrl: nil).displayCoverURL(meta: nil) == nil)
    }

    @Test func appearanceIsStablePerBook() {
        #expect(BookAppearance(bookId: "book-dune").spineHeight == BookAppearance(bookId: "book-dune").spineHeight)
    }
}
