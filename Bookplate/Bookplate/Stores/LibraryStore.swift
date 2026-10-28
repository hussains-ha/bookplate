import Foundation
import Observation

/// In-memory source of truth for the current library.
// TODO(supabase): load these from and save them to Postgres through supabase-swift (one library per user,
// shared libraries behind row level security). Every mutating method below is a place that needs to write through.
@MainActor
@Observable
final class LibraryStore {
    private(set) var books: [Book]
    private(set) var metas: [BookMeta]
    private(set) var bookshelf: Bookshelf
    private(set) var lists: [BookList] = []

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
        let store = LibraryStore(books: books, metas: metas, bookshelf: bookshelf)
        store.lists = (try? BookList.sampleFromBundle()) ?? BookList.mocks
        return store
    }

    var defaultShelfId: String? { bookshelf.shelves.first?.id }

    func book(withId id: String) -> Book? { books.first { $0.id == id } }

    func meta(for bookId: String) -> BookMeta? { metas.first { $0.bookId == bookId } }

    /// The shelves a book is on.
    func shelves(containing bookId: String) -> [Shelf] {
        bookshelf.shelves.filter { $0.bookIds.contains(bookId) }
    }

    /// The lists a book is on.
    func lists(containing bookId: String) -> [BookList] {
        lists.filter { $0.bookIds.contains(bookId) }
    }

    func addList(_ list: BookList) {
        lists.append(list)
    }

    /// Adds a book to a list, or removes it.
    func setBook(_ bookId: String, inList listId: String, to isInList: Bool) {
        guard book(withId: bookId) != nil, let index = lists.firstIndex(where: { $0.id == listId }) else { return }
        let present = lists[index].bookIds.contains(bookId)
        if isInList, !present {
            lists[index].bookIds.append(bookId)
        } else if !isInList, present {
            lists[index].bookIds.removeAll { $0 == bookId }
        }
    }

    // MARK: Personal details

    private func updateMeta(_ bookId: String, _ change: (inout BookMeta) -> Void) {
        guard let index = metas.firstIndex(where: { $0.bookId == bookId }) else { return }
        change(&metas[index])
    }

    func setStatus(_ status: String, for bookId: String) {
        updateMeta(bookId) { $0.status = status }
    }

    /// 1...5 stars, or nil to clear. Anything else is ignored.
    func setRating(_ rating: Int?, for bookId: String) {
        guard rating == nil || (1...5).contains(rating!) else { return }
        updateMeta(bookId) { $0.rating = rating }
    }

    func setNotes(_ notes: String, for bookId: String) {
        updateMeta(bookId) { $0.notes = notes.isEmpty ? nil : notes }
    }

    /// Adds a tag, ignoring blanks and tags the book already has (case-insensitive).
    func addTag(_ tag: String, to bookId: String) {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        updateMeta(bookId) { meta in
            guard !tag.isEmpty, !meta.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
            meta.tags.append(tag)
        }
    }

    func removeTag(_ tag: String, from bookId: String) {
        updateMeta(bookId) { $0.tags.removeAll { $0 == tag } }
    }

    func addNotePhoto(_ url: URL, to bookId: String) {
        updateMeta(bookId) { $0.notePhotos.append(url) }
    }

    func removeNotePhoto(_ url: URL, from bookId: String) {
        updateMeta(bookId) { $0.notePhotos.removeAll { $0 == url } }
    }

    /// Sets the user's own cover for a book, or nil to go back to the official or generated cover.
    func setCustomCover(_ url: URL?, for bookId: String) {
        updateMeta(bookId) { $0.customCover = url }
    }

    /// Removes a book everywhere: its details, its place on every shelf and every list.
    // TODO(supabase): also delete the book's uploaded images (custom cover and note photos) from storage.
    func removeBook(_ bookId: String) {
        books.removeAll { $0.id == bookId }
        metas.removeAll { $0.bookId == bookId }
        for index in bookshelf.shelves.indices {
            bookshelf.shelves[index].bookIds.removeAll { $0 == bookId }
        }
        for index in lists.indices {
            lists[index].bookIds.removeAll { $0 == bookId }
        }
    }

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
