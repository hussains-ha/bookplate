import Foundation

/// A whole bookshelf (one per library) made up of ordered shelves.
struct Bookshelf: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var shelves: [Shelf]
    var appearance: Appearance

    enum Appearance: String, Codable, CaseIterable, Sendable {
        case classic
        case maple
        case modern
    }
}

extension Bookshelf {
    static let mock = Bookshelf(
        id: "bookshelf-abigail",
        name: "Abigail's Library",
        shelves: Shelf.mocks,
        appearance: .classic
    )

    static let mocks: [Bookshelf] = [
        .mock,
        Bookshelf(id: "bookshelf-book-club", name: "Book Club Picks",
                  shelves: [Shelf(id: "shelf-picks", name: "Our picks this year",
                                  bookIds: ["book-dune", "book-educated"])],
                  appearance: .maple),
        Bookshelf(id: "bookshelf-dad", name: "Dad's Mystery Shelf",
                  shelves: [], appearance: .modern),
    ]

    /// Decodes the bundled `bookshelves.json` sample data.
    static func sampleFromBundle(_ bundle: Bundle = .main) throws -> [Bookshelf] {
        guard let url = bundle.url(forResource: "bookshelves", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Bookshelf].self, from: Data(contentsOf: url))
    }
}
