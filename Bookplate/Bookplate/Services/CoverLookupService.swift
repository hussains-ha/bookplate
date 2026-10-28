import Foundation

/// What a cover lookup found for a book. Either field may be missing.
struct CoverLookupResult: Equatable, Sendable {
    var coverURL: URL?
    var pageCount: Int?
}

protocol CoverLookup: Sendable {
    /// Returns nil when nothing was found anywhere. Throws on network or server errors, so the caller can try again later.
    func lookup(title: String, author: String?, isbn: String?) async throws -> CoverLookupResult?
}

/// The network calls the lookup needs, so tests can pass a mock instead of the real network.
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    var session: URLSession = .shared

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Finds covers on Open Library (by ISBN) and Google Books (by title and author).
struct CoverLookupService: CoverLookup {
    var client: HTTPClient = URLSessionHTTPClient()

    func lookup(title: String, author: String?, isbn: String?) async throws -> CoverLookupResult? {
        if let isbn, !isbn.isEmpty, let url = Self.openLibraryURL(isbn: isbn), try await exists(url) {
            return CoverLookupResult(coverURL: url, pageCount: nil)
        }
        return try await googleBooksResult(title: title, author: author)
    }

    // MARK: URLs

    static func openLibraryURL(isbn: String) -> URL? {
        URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg?default=false")
    }

    static func googleBooksSearchURL(title: String, author: String?) -> URL? {
        var query = "intitle:\(title)"
        if let author, !author.isEmpty { query += " inauthor:\(author)" }
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "1"),
        ]
        return components?.url
    }

    /// Google returns `http` thumbnails with a page-curl edge and a small zoom; ask for a clean, larger image.
    static func cleanGoogleCoverURL(_ raw: String) -> URL? {
        guard var components = URLComponents(string: raw) else { return nil }
        components.scheme = "https"
        components.queryItems = components.queryItems?
            .filter { $0.name != "edge" }
            .map { $0.name == "zoom" && $0.value == "1" ? URLQueryItem(name: "zoom", value: "2") : $0 }
        return components.url
    }

    // MARK: Requests

    private func exists(_ url: URL) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await client.data(for: request)
        // Open Library answers 404 (not a blank image) when `default=false` and there is no cover.
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private func googleBooksResult(title: String, author: String?) async throws -> CoverLookupResult? {
        guard let url = Self.googleBooksSearchURL(title: title, author: author) else { return nil }
        let (data, response) = try await client.data(for: URLRequest(url: url))
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        guard let volume = try? JSONDecoder().decode(GoogleBooksResponse.self, from: data).items?.first?.volumeInfo else {
            return nil
        }
        let coverURL = volume.imageLinks?.thumbnail.flatMap(Self.cleanGoogleCoverURL)
        guard coverURL != nil || volume.pageCount != nil else { return nil }
        return CoverLookupResult(coverURL: coverURL, pageCount: volume.pageCount)
    }
}

private struct GoogleBooksResponse: Decodable {
    struct Item: Decodable { let volumeInfo: VolumeInfo }
    struct VolumeInfo: Decodable {
        let pageCount: Int?
        let imageLinks: ImageLinks?
    }
    struct ImageLinks: Decodable { let thumbnail: String? }

    let items: [Item]?
}
