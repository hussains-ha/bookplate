import Foundation

/// A user-made group of books, shown to users as a "List" or "Bookmark List". Books are referenced by `Book.id`.
struct BookList: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var bookIds: [String]
}

extension BookList {
    static let mock = BookList(
        id: "list-book-club",
        name: "Book Club Picks",
        bookIds: ["book-dune", "book-educated"]
    )

    static let mocks: [BookList] = [
        .mock,
        BookList(id: "list-self-improvement", name: "Self-Improvement", bookIds: ["book-atomic-habits"]),
        BookList(id: "list-to-reread", name: "To Re-read", bookIds: ["book-good-omens", "book-sapiens"]),
        BookList(id: "list-empty", name: "Someday", bookIds: []),
    ]

    /// Decodes the bundled `booklist.json` sample data.
    static func sampleFromBundle(_ bundle: Bundle = .main) throws -> [BookList] {
        guard let url = bundle.url(forResource: "booklist", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([BookList].self, from: Data(contentsOf: url))
    }
}
