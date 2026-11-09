import Foundation
import Observation

/// Source of truth for the current library. Signed-in libraries save every change through `LibrarySync`;
/// the sample library (dev skip, previews, tests) has no sync and stays in memory.
@MainActor
@Observable
final class LibraryStore {
    private(set) var books: [Book]
    private(set) var metas: [BookMeta]
    private(set) var bookshelf: Bookshelf
    private(set) var lists: [BookList] = []

    static let recentlyAddedName = "Recently Added"

    private let coverLookup: CoverLookup
    private var lookupsInFlight: Set<String> = []
    private let sync: LibrarySync?
    private let localFiles: LocalBookFiles?

    init(books: [Book], metas: [BookMeta], bookshelf: Bookshelf, lists: [BookList] = [],
         coverLookup: CoverLookup? = nil, sync: LibrarySync? = nil, localFiles: LocalBookFiles? = nil) {
        self.books = books
        self.metas = metas
        self.bookshelf = bookshelf
        self.lists = lists
        self.coverLookup = coverLookup ?? CoverLookupService()
        self.sync = sync
        self.localFiles = localFiles
    }

    /// A signed-in user's library, loaded from Supabase. Covers and note photos come from the device.
    static func loaded(_ snapshot: LibrarySnapshot, userId: UUID, sync: LibrarySync,
                       localFiles: LocalBookFiles?, coverLookup: CoverLookup? = nil) -> LibraryStore {
        let bookshelf = Bookshelf(id: "bookshelf-\(userId.uuidString.lowercased())", name: "My Library",
                                  shelves: snapshot.shelves, appearance: .classic)
        return LibraryStore(books: snapshot.books, metas: localFiles?.apply(to: snapshot.metas) ?? snapshot.metas,
                            bookshelf: bookshelf, lists: snapshot.lists, coverLookup: coverLookup,
                            sync: sync, localFiles: localFiles)
    }

    var syncStatus: LibrarySync.Status { sync?.status ?? .idle }
    func retrySync() { sync?.retryNow() }
    func dismissSyncRejection() { sync?.dismissRejection() }
    func stopSync() { sync?.stop() }

    // MARK: Saving

    private func save(_ change: LibraryChange) { sync?.enqueue(change) }

    private func saveShelf(at index: Int) {
        save(.saveShelf(bookshelf.shelves[index], position: index))
    }

    private func saveShelfBooks(at index: Int) {
        let shelf = bookshelf.shelves[index]
        save(.setShelfBooks(shelfId: shelf.id, bookIds: shelf.bookIds))
    }

    private func saveListBooks(at index: Int) {
        save(.setListBooks(listId: lists[index].id, bookIds: lists[index].bookIds))
    }

    private func saveLocalFiles() { localFiles?.save(metas) }

    /// Loads the bundled sample data, falling back to the in-code mocks.
    static func sample() -> LibraryStore {
        let books = (try? Book.sampleFromBundle()) ?? Book.mocks
        let metas = (try? BookMeta.sampleFromBundle()) ?? BookMeta.mocks
        let bookshelf = ((try? Bookshelf.sampleFromBundle()) ?? Bookshelf.mocks).first ?? .mock
        let lists = (try? BookList.sampleFromBundle()) ?? BookList.mocks
        return LibraryStore(books: books, metas: metas, bookshelf: bookshelf, lists: lists)
    }

    /// The shelf new books go to by default: the first one that isn't locked.
    var defaultShelfId: String? { bookshelf.shelves.first { !$0.isLocked }?.id }

    /// True when there are shelves but none can take new books.
    var allShelvesLocked: Bool { !bookshelf.shelves.isEmpty && bookshelf.shelves.allSatisfy(\.isLocked) }

    func setLocked(_ locked: Bool, onShelf shelfId: String) {
        guard let index = bookshelf.shelves.firstIndex(where: { $0.id == shelfId }) else { return }
        guard bookshelf.shelves[index].isLocked != locked else { return }
        bookshelf.shelves[index].isLocked = locked
        saveShelf(at: index)
    }

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
        save(.saveList(list, position: lists.count - 1))
        if !list.bookIds.isEmpty { saveListBooks(at: lists.count - 1) }
    }

    /// Adds a book to a list, or removes it.
    func setBook(_ bookId: String, inList listId: String, to isInList: Bool) {
        guard book(withId: bookId) != nil, let index = lists.firstIndex(where: { $0.id == listId }) else { return }
        let present = lists[index].bookIds.contains(bookId)
        if isInList, !present {
            lists[index].bookIds.append(bookId)
        } else if !isInList, present {
            lists[index].bookIds.removeAll { $0 == bookId }
        } else {
            return
        }
        saveListBooks(at: index)
    }

    // MARK: Personal details

    /// Applies a change to a book's details and saves them if anything changed.
    /// `local` changes (custom cover, note photos) are saved on the device instead.
    private func updateMeta(_ bookId: String, local: Bool = false, _ change: (inout BookMeta) -> Void) {
        guard let index = metas.firstIndex(where: { $0.bookId == bookId }) else { return }
        let before = metas[index]
        change(&metas[index])
        guard metas[index] != before else { return }
        if local {
            saveLocalFiles()
        } else {
            save(.saveMeta(metas[index]))
        }
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
        updateMeta(bookId, local: true) { $0.notePhotos.append(url) }
    }

    func removeNotePhoto(_ url: URL, from bookId: String) {
        updateMeta(bookId, local: true) { $0.notePhotos.removeAll { $0 == url } }
    }

    /// Sets the user's own cover for a book, or nil to go back to the official or generated cover.
    func setCustomCover(_ url: URL?, for bookId: String) {
        updateMeta(bookId, local: true) { $0.customCover = url }
    }

    /// Removes a book everywhere: its details, its place on every shelf and every list.
    // TODO(supabase): also delete the book's uploaded images (custom cover and note photos) from storage.
    func removeBook(_ bookId: String) {
        guard book(withId: bookId) != nil else { return }
        books.removeAll { $0.id == bookId }
        metas.removeAll { $0.bookId == bookId }
        for index in bookshelf.shelves.indices {
            bookshelf.shelves[index].bookIds.removeAll { $0 == bookId }
        }
        for index in lists.indices {
            lists[index].bookIds.removeAll { $0 == bookId }
        }
        // The database removes the book's details and shelf and list entries with it.
        save(.deleteBook(id: bookId))
        saveLocalFiles()
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

    struct DuplicateCheck: Equatable {
        var match: Book?
        /// True when the server couldn't be asked, so only this device's books were checked.
        var checkedDeviceOnly = false
    }

    /// Looks for an existing book with the same title and author in the user's online library,
    /// falling back to the books on this device when the server can't be reached.
    func checkDuplicate(title: String, author: String) async -> DuplicateCheck {
        let local = findDuplicate(title: title, author: author)
        guard let repository = sync?.repository else { return DuplicateCheck(match: local) }
        do {
            let candidates = try await repository.books(titled: title.trimmingCharacters(in: .whitespacesAndNewlines))
            // Books added on this device that haven't been saved yet only show up locally.
            return DuplicateCheck(match: Self.firstMatch(in: candidates, title: title, author: author) ?? local)
        } catch {
            return DuplicateCheck(match: local, checkedDeviceOnly: true)
        }
    }

    /// An existing book with the same title and author, if any.
    func findDuplicate(title: String, author: String) -> Book? {
        Self.firstMatch(in: books, title: title, author: author)
    }

    private static func firstMatch(in books: [Book], title: String, author: String) -> Book? {
        let title = normalize(title)
        let author = normalize(author)
        return books.first { book in
            normalize(book.title) == title
                && (author.isEmpty || book.authors.contains { normalize($0) == author })
        }
    }

    /// Moves a book to a new position on the same shelf. `index` is its final position, clamped to the shelf.
    /// Returns false when nothing changed (unknown or locked shelf, unknown book, or the book is already there).
    @discardableResult
    func moveBook(_ bookId: String, onShelf shelfId: String, to index: Int) -> Bool {
        guard let shelfIndex = bookshelf.shelves.firstIndex(where: { $0.id == shelfId }),
              !bookshelf.shelves[shelfIndex].isLocked,
              let from = bookshelf.shelves[shelfIndex].bookIds.firstIndex(of: bookId) else { return false }
        var ids = bookshelf.shelves[shelfIndex].bookIds
        let to = min(max(index, 0), ids.count - 1)
        guard to != from else { return false }
        ids.insert(ids.remove(at: from), at: to)
        bookshelf.shelves[shelfIndex].bookIds = ids
        saveShelfBooks(at: shelfIndex)
        return true
    }

    /// Adds a book to the front of the target shelf, creating the default shelf if none exist.
    /// A locked or missing target falls back to the first unlocked shelf. Returns nil, adding nothing, when every shelf is locked.
    @discardableResult
    func addBook(title: String, author: String, pageCount: Int?, shelfId: String?) -> Book? {
        guard !allShelvesLocked else { return nil }
        let author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let book = Book(
            id: "book-\(UUID().uuidString.lowercased())",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            authors: author.isEmpty ? [] : [author],
            pageCount: pageCount,
            coverUrl: nil,
            isbn13: nil
        )
        let meta = BookMeta(
            bookId: book.id, status: BookMeta.Status.want, rating: nil, notes: nil,
            notePhotos: [], tags: [], customCover: nil,
            addedDate: Date(), startedDate: nil, finishedDate: nil
        )
        books.append(book)
        metas.append(meta)
        save(.saveBook(book))
        save(.saveMeta(meta))

        let requested = bookshelf.shelves.firstIndex { $0.id == shelfId && !$0.isLocked }
        if let index = requested ?? bookshelf.shelves.firstIndex(where: { !$0.isLocked }) {
            bookshelf.shelves[index].bookIds.insert(book.id, at: 0)
            saveShelfBooks(at: index)
        } else {
            bookshelf.shelves.append(Shelf(
                id: "shelf-\(UUID().uuidString.lowercased())",
                name: Self.recentlyAddedName,
                bookIds: [book.id]
            ))
            saveShelf(at: bookshelf.shelves.count - 1)
            saveShelfBooks(at: bookshelf.shelves.count - 1)
        }
        Task { await fillCover(for: book.id) }
        return book
    }

    /// Looks up an official cover (and a page count, if missing) for a book and saves what is found.
    /// Each book is only marked as tried once a lookup finishes, so a network failure is retried later.
    func fillCover(for bookId: String) async {
        guard let book = books.first(where: { $0.id == bookId }),
              book.coverLookupAttempted != true,
              lookupsInFlight.insert(bookId).inserted else { return }
        defer { lookupsInFlight.remove(bookId) }

        let result: CoverLookupResult?
        do {
            result = try await coverLookup.lookup(title: book.title, author: book.authors.first, isbn: book.isbn13)
        } catch {
            return
        }
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return }
        if books[index].coverUrl == nil { books[index].coverUrl = result?.coverURL }
        if books[index].pageCount == nil { books[index].pageCount = result?.pageCount }
        books[index].coverLookupAttempted = true
        save(.saveBook(books[index]))
    }

    /// Tries to find covers for existing books that have none, once each.
    func backfillCovers() async {
        let ids = books.filter { $0.coverUrl == nil && $0.coverLookupAttempted != true }.map(\.id)
        for id in ids { await fillCover(for: id) }
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
