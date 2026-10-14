import Foundation
import Observation

/// In-memory source of truth for the current library.
@MainActor
@Observable
final class LibraryStore {
    private(set) var books: [Book]
    private(set) var metas: [BookMeta]
    private(set) var bookshelf: Bookshelf

    static let recentlyAddedName = "Recently Added"

    init(books: [Book], metas: [BookMeta], bookshelf: Bookshelf) {
        self.books = books
        self.metas = metas
        self.bookshelf = bookshelf
    }

    /// Loads the bundled sample data, falling back to the in-code mocks.
    static func sample() -> LibraryStore {
        let books = (try? Book.sampleFromBundle()) ?? Book.mocks
        let metas = (try? BookMeta.sampleFromBundle()) ?? BookMeta.mocks
        let bookshelf = ((try? Bookshelf.sampleFromBundle()) ?? Bookshelf.mocks).first ?? .mock
        return LibraryStore(books: books, metas: metas, bookshelf: bookshelf)
    }

    var defaultShelfId: String? { bookshelf.shelves.first?.id }

    /// Books on a shelf in shelf order, optionally filtered by a title/author query.
    func books(on shelf: Shelf, matching query: String = "") -> [Book] {
        let byId = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let onShelf = shelf.bookIds.compactMap { byId[$0] }
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return onShelf }
        return onShelf.filter { book in
            Self.normalize(book.title).contains(needle)
                || book.authors.contains { Self.normalize($0).contains(needle) }
        }
    }

    /// An existing book with the same title and author, if any.
    func findDuplicate(title: String, author: String) -> Book? {
        let title = Self.normalize(title)
        let author = Self.normalize(author)
        return books.first { book in
            Self.normalize(book.title) == title
                && (author.isEmpty || book.authors.contains { Self.normalize($0) == author })
        }
    }

    /// Adds a book to the front of the target shelf, creating the default shelf if none exist.
    @discardableResult
    func addBook(title: String, author: String, pageCount: Int?, shelfId: String?) -> Book {
        let author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let book = Book(
            id: "book-\(UUID().uuidString.lowercased())",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: author.isEmpty ? [] : [author],
            pageCount: pageCount,
            coverUrl: nil,
            isbn13: nil
        )
        books.append(book)
        metas.append(BookMeta(
            bookId: book.id, status: BookMeta.Status.want, rating: nil, notes: nil,
            notePhotos: [], tags: [], customCover: nil,
            addedDate: Date(), startedDate: nil, finishedDate: nil
        ))

        if let index = bookshelf.shelves.firstIndex(where: { $0.id == shelfId }) {
            bookshelf.shelves[index].bookIds.insert(book.id, at: 0)
        } else if bookshelf.shelves.isEmpty {
            bookshelf.shelves.append(Shelf(
                id: "shelf-\(UUID().uuidString.lowercased())",
                name: Self.recentlyAddedName,
                bookIds: [book.id]
            ))
        } else {
            bookshelf.shelves[0].bookIds.insert(book.id, at: 0)
        }
        return book
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
