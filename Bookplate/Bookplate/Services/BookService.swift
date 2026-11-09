import Foundation
import Supabase

/// Errors from reading or writing books, worded for the UI.
enum BookServiceError: Error, Equatable, LocalizedError {
    case notSignedIn
    case network
    case decoding
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Sign in to sync your library."
        case .network: "Can't reach Bookplate. Check your connection and try again."
        case .decoding: "Bookplate received data it couldn't read."
        case .server(let message): message
        }
    }
}

/// The signed-in user's books. `BookService` talks to Supabase; `InMemoryBookRepository` is for tests and previews.
protocol BookRepository {
    /// All of the user's books, oldest first.
    func fetchBooks() async throws(BookServiceError) -> [Book]
    func addBook(_ book: Book) async throws(BookServiceError)
    func updateBook(_ book: Book) async throws(BookServiceError)
    func deleteBook(id: String) async throws(BookServiceError)
}

/// A `books` table row. `user_id` is filled in by the database from the session,
/// and row-level security limits every query to the signed-in user's rows.
struct BookRow: Codable, Equatable {
    var id: String
    var title: String
    var authors: [String]
    var pageCount: Int?
    var coverUrl: String?
    var isbn13: String?
    var coverLookupAttempted: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, authors, isbn13
        case pageCount = "page_count"
        case coverUrl = "cover_url"
        case coverLookupAttempted = "cover_lookup_attempted"
    }

    init(_ book: Book) {
        id = book.id
        title = book.title
        authors = book.authors
        pageCount = book.pageCount
        coverUrl = book.coverUrl?.absoluteString
        isbn13 = book.isbn13
        coverLookupAttempted = book.coverLookupAttempted
    }

    var book: Book {
        Book(id: id, title: title, authors: authors, pageCount: pageCount,
             coverUrl: coverUrl.flatMap(URL.init(string:)), isbn13: isbn13,
             coverLookupAttempted: coverLookupAttempted)
    }
}

struct BookService: BookRepository {
    var client: SupabaseClient = SupabaseService.client
    private var table: PostgrestQueryBuilder { client.from("books") }

    func fetchBooks() async throws(BookServiceError) -> [Book] {
        try await run {
            let rows: [BookRow] = try await table.select().order("created_at").execute().value
            return rows.map(\.book)
        }
    }

    func addBook(_ book: Book) async throws(BookServiceError) {
        try await run { try await table.insert(BookRow(book)).execute() }
    }

    func updateBook(_ book: Book) async throws(BookServiceError) {
        try await run {
            try await table.update(BookRow(book), returning: .minimal).eq("id", value: book.id).execute()
        }
    }

    func deleteBook(id: String) async throws(BookServiceError) {
        try await run { try await table.delete().eq("id", value: id).execute() }
    }

    /// Checks for a session, runs the request and maps any error to `BookServiceError`.
    @discardableResult
    private func run<T>(_ request: () async throws -> T) async throws(BookServiceError) -> T {
        guard client.auth.currentSession != nil else { throw .notSignedIn }
        do {
            return try await request()
        } catch {
            throw Self.failure(from: error)
        }
    }

    static func failure(from error: Error) -> BookServiceError {
        switch error {
        case is URLError: .network
        case is DecodingError: .decoding
        // PGRST301/PGRST303: the session's token was rejected or expired.
        case let error as PostgrestError where ["PGRST301", "PGRST303"].contains(error.code): .notSignedIn
        case let error as PostgrestError: .server(error.message)
        default: .server(error.localizedDescription)
        }
    }
}

/// Keeps books in memory. Used by tests and previews, and as a stand-in before sign-in.
final class InMemoryBookRepository: BookRepository {
    private(set) var books: [Book]

    init(books: [Book] = []) {
        self.books = books
    }

    func fetchBooks() async throws(BookServiceError) -> [Book] { books }

    func addBook(_ book: Book) async throws(BookServiceError) {
        guard !books.contains(where: { $0.id == book.id }) else { throw .server("Book \(book.id) already exists.") }
        books.append(book)
    }

    func updateBook(_ book: Book) async throws(BookServiceError) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
    }

    func deleteBook(id: String) async throws(BookServiceError) {
        books.removeAll { $0.id == id }
    }
}
