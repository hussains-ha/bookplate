import Foundation
import Testing
@testable import Bookplate

struct CoverLookupServiceTests {
    /// Answers each request with a canned status and body, and records the requests it saw.
    final class MockHTTPClient: HTTPClient, @unchecked Sendable {
        var handler: (URLRequest) throws -> (Int, Data)
        private(set) var requests: [URLRequest] = []

        init(_ handler: @escaping (URLRequest) throws -> (Int, Data)) { self.handler = handler }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    private func json(_ text: String) -> Data { Data(text.utf8) }

    private let googleHit = """
    {"items":[{"volumeInfo":{"pageCount":352,"imageLinks":{"thumbnail":"http://books.google.com/books/content?id=abc&printsec=frontcover&img=1&zoom=1&edge=curl&source=gbs_api"}}}]}
    """

    // MARK: URL building and cleanup

    @Test func openLibraryURLUsesDefaultFalse() {
        #expect(CoverLookupService.openLibraryURL(isbn: "9780441013593")?.absoluteString
                == "https://covers.openlibrary.org/b/isbn/9780441013593-L.jpg?default=false")
    }

    @Test func googleSearchURLIncludesTitleAndAuthor() throws {
        let url = try #require(CoverLookupService.googleBooksSearchURL(title: "Good Omens", author: "Terry Pratchett"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "q" }?.value == "intitle:Good Omens inauthor:Terry Pratchett")
    }

    @Test func googleSearchURLOmitsMissingAuthor() throws {
        let url = try #require(CoverLookupService.googleBooksSearchURL(title: "Dune", author: nil))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "q" }?.value == "intitle:Dune")
    }

    @Test func cleanupForcesHTTPSDropsEdgeAndRaisesZoom() throws {
        let cleaned = try #require(CoverLookupService.cleanGoogleCoverURL(
            "http://books.google.com/books/content?id=abc&zoom=1&edge=curl&source=gbs_api"))
        #expect(cleaned.scheme == "https")
        #expect(!cleaned.absoluteString.contains("edge=curl"))
        #expect(cleaned.absoluteString.contains("zoom=2"))
        #expect(cleaned.absoluteString.contains("id=abc"))
    }

    // MARK: Lookup

    @Test func isbnUsesOpenLibraryWhenCoverExists() async throws {
        let client = MockHTTPClient { _ in (200, Data()) }
        let result = try await CoverLookupService(client: client).lookup(title: "Dune", author: "Frank Herbert", isbn: "9780441013593")
        #expect(result?.coverURL?.host == "covers.openlibrary.org")
        #expect(client.requests.count == 1)
    }

    @Test func isbnWithoutOpenLibraryCoverFallsBackToGoogle() async throws {
        let client = MockHTTPClient { [googleHit] request in
            request.url?.host == "covers.openlibrary.org" ? (404, Data()) : (200, Data(googleHit.utf8))
        }
        let result = try await CoverLookupService(client: client).lookup(title: "Educated", author: "Tara Westover", isbn: "9780399590504")
        #expect(result?.coverURL?.host == "books.google.com")
        #expect(result?.pageCount == 352)
    }

    @Test func noISBNSearchesGoogleAndCleansURL() async throws {
        let client = MockHTTPClient { [googleHit] _ in (200, Data(googleHit.utf8)) }
        let result = try await CoverLookupService(client: client).lookup(title: "Educated", author: "Tara Westover", isbn: nil)
        #expect(result?.coverURL?.scheme == "https")
        #expect(result?.coverURL?.absoluteString.contains("zoom=2") == true)
        #expect(result?.pageCount == 352)
    }

    // MARK: "No result" handling

    @Test func emptyResultsReturnNil() async throws {
        let client = MockHTTPClient { _ in (200, Data(#"{"totalItems":0}"#.utf8)) }
        #expect(try await CoverLookupService(client: client).lookup(title: "Nope", author: nil, isbn: nil) == nil)
    }

    @Test func resultWithoutImageLinksOrPagesReturnsNil() async throws {
        let client = MockHTTPClient { _ in (200, Data(#"{"items":[{"volumeInfo":{}}]}"#.utf8)) }
        #expect(try await CoverLookupService(client: client).lookup(title: "Nope", author: nil, isbn: nil) == nil)
    }

    @Test func malformedJSONReturnsNil() async throws {
        let client = MockHTTPClient { _ in (200, Data("not json".utf8)) }
        #expect(try await CoverLookupService(client: client).lookup(title: "Nope", author: nil, isbn: nil) == nil)
    }

    @Test func serverErrorThrowsSoItCanBeRetried() async {
        let client = MockHTTPClient { _ in (503, Data()) }
        await #expect(throws: URLError.self) {
            try await CoverLookupService(client: client).lookup(title: "Dune", author: nil, isbn: nil)
        }
    }

    @Test func networkErrorThrows() async {
        let client = MockHTTPClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) {
            try await CoverLookupService(client: client).lookup(title: "Dune", author: nil, isbn: nil)
        }
    }
}
