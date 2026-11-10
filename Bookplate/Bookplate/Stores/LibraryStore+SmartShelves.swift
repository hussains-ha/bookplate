import Foundation

/// Read-only shelves worked out from each book's details. They sit above the regular shelves.
enum SmartShelf: String, CaseIterable, Sendable {
    case reading
    case want
    case favorites

    /// Never saved, and can't clash with a real shelf (those are `shelf-<uuid>` or seeded `shelf-…` ids).
    var id: String { "smart-\(rawValue)" }

    var name: String {
        switch self {
        case .reading: "Currently Reading"
        case .want: "Want to Read"
        case .favorites: "Favorites"
        }
    }

    /// The same rule as the matching filter-menu item.
    var filter: LibraryFilter {
        switch self {
        case .reading: .status(BookMeta.Status.reading)
        case .want: .status(BookMeta.Status.want)
        case .favorites: .favorites
        }
    }

    static func isSmart(_ shelfId: String) -> Bool { allCases.contains { $0.id == shelfId } }
}

extension LibraryStore {
    /// Smart shelves that have books, in order (Currently Reading, Want to Read, Favorites).
    /// Books appear in bookcase order: shelf by shelf, then any book not on a shelf.
    func smartShelves() -> [VisibleShelf] {
        let order = libraryOrder()
        return SmartShelf.allCases.compactMap { smart in
            let shelf = Shelf(id: smart.id, name: smart.name, bookIds: order)
            let books = books(on: shelf, filter: smart.filter)
            guard !books.isEmpty else { return nil }
            return VisibleShelf(shelf: Shelf(id: smart.id, name: smart.name, bookIds: books.map(\.id)), books: books)
        }
    }

    /// Every book id once, in the order the bookcase shows them.
    private func libraryOrder() -> [String] {
        var seen = Set<String>()
        let onShelves = bookshelf.shelves.flatMap(\.bookIds).filter { seen.insert($0).inserted }
        return onShelves + books.map(\.id).filter { seen.insert($0).inserted }
    }
}
