import Foundation

/// A book's objective, immutable data. Personal details live in `BookMeta`.
struct Book: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let authors: [String]
    var pageCount: Int?
    var coverUrl: URL?
    /// Unique book identifier, when known.
    let isbn13: String?
    /// Set once an automatic cover lookup has finished, so books with no cover aren't looked up forever.
    var coverLookupAttempted: Bool?
}

extension Book {
    static let mock = Book(
        id: "book-atomic-habits",
        title: "Atomic Habits",
        authors: ["James Clear"],
        pageCount: 320,
        coverUrl: URL(string: "https://covers.openlibrary.org/b/isbn/9780735211292-L.jpg?default=false"),
        isbn13: "9780735211292"
    )

    static let mocks: [Book] = [
        .mock,
        Book(id: "book-dune", title: "Dune", authors: ["Frank Herbert"],
             pageCount: 688,
             coverUrl: URL(string: "https://covers.openlibrary.org/b/isbn/9780441013593-L.jpg?default=false"), isbn13: "9780441013593"),
        Book(id: "book-educated", title: "Educated", authors: ["Tara Westover"],
             pageCount: 352,
             coverUrl: URL(string: "https://covers.openlibrary.org/b/isbn/9780399590504-L.jpg?default=false"), isbn13: "9780399590504"),
        Book(id: "book-good-omens", title: "Good Omens", authors: ["Terry Pratchett", "Neil Gaiman"],
             pageCount: nil, coverUrl: nil, isbn13: nil),
    ]

    /// Decodes the bundled `books.json` sample data.
    static func sampleFromBundle(_ bundle: Bundle = .main) throws -> [Book] {
        guard let url = bundle.url(forResource: "books", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Book].self, from: Data(contentsOf: url))
    }
}
