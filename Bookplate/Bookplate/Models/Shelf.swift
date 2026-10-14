import Foundation

/// A named, ordered group of books. Books are referenced by `Book.id`.
struct Shelf: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var bookIds: [String]
}

extension Shelf {
    static let mock = Shelf(
        id: "shelf-recently-added",
        name: "Recently Added",
        bookIds: ["book-atomic-habits", "book-dune"]
    )

    static let mocks: [Shelf] = [
        .mock,
        Shelf(id: "shelf-fiction", name: "Fiction & Classics", bookIds: ["book-dune", "book-good-omens"]),
        Shelf(id: "shelf-memoir", name: "Memoir & Biography", bookIds: ["book-educated"]),
        Shelf(id: "shelf-empty", name: "Someday", bookIds: []),
    ]

    /// Decodes the bundled `shelves.json` sample data.
    static func sampleFromBundle(_ bundle: Bundle = .main) throws -> [Shelf] {
        guard let url = bundle.url(forResource: "shelves", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Shelf].self, from: Data(contentsOf: url))
    }
}
