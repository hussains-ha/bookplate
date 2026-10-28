import Foundation

/// A named, ordered group of books. Books are referenced by `Book.id`.
struct Shelf: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var bookIds: [String]
    /// Locked shelves can't have books added, moved onto, or rearranged.
    var isLocked = false

    enum CodingKeys: String, CodingKey {
        case id, name, bookIds, isLocked
    }
}

extension Shelf {
    /// `isLocked` is optional in JSON so files saved before locking existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bookIds = try container.decode([String].self, forKey: .bookIds)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }
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
