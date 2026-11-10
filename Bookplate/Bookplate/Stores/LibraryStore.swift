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
    /// Recent deletions, newest last, so they can be undone.
    private(set) var undoStack: [Deletion] = []

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

    // MARK: Shelves

    static let maxShelfNameLength = 40

    enum ShelfNameProblem: Equatable {
        case blank, tooLong, duplicate

        var message: String {
            switch self {
            case .blank: "Enter a name for the shelf."
            case .tooLong: "Shelf names can be up to \(LibraryStore.maxShelfNameLength) characters."
            case .duplicate: "You already have a shelf with that name."
            }
        }
    }

    /// Why a name can't be used for a shelf, or nil if it can. Names are compared trimmed and ignoring case.
    /// Pass the shelf being renamed as `excluding` so it doesn't clash with its own name.
    func shelfNameProblem(_ name: String, excluding shelfId: String? = nil) -> ShelfNameProblem? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .blank }
        if name.count > Self.maxShelfNameLength { return .tooLong }
        let taken = bookshelf.shelves.contains {
            $0.id != shelfId
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
        }
        return taken ? .duplicate : nil
    }

    /// Adds an empty shelf at the bottom of the bookcase. Returns nil, adding nothing, if the name can't be used.
    @discardableResult
    func addShelf(named name: String) -> Shelf? {
        guard shelfNameProblem(name) == nil else { return nil }
        let shelf = Shelf(
            id: "shelf-\(UUID().uuidString.lowercased())",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            bookIds: []
        )
        bookshelf.shelves.append(shelf)
        saveShelf(at: bookshelf.shelves.count - 1)
        return shelf
    }

    /// Renames a shelf (locked or not). Returns the problem, changing nothing, if the name can't be used.
    @discardableResult
    func renameShelf(_ shelfId: String, to name: String) -> ShelfNameProblem? {
        guard let index = bookshelf.shelves.firstIndex(where: { $0.id == shelfId }) else { return nil }
        if let problem = shelfNameProblem(name, excluding: shelfId) { return problem }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != bookshelf.shelves[index].name else { return nil }
        bookshelf.shelves[index].name = name
        saveShelf(at: index)
        return nil
    }

    /// Moves a shelf (locked or not) to a new spot in the bookcase, clamped to the ends.
    /// Every shelf's position is saved, which also repairs positions that drifted (e.g. edits from two devices).
    func moveShelf(_ shelfId: String, to index: Int) {
        guard let from = bookshelf.shelves.firstIndex(where: { $0.id == shelfId }) else { return }
        let to = min(max(index, 0), bookshelf.shelves.count - 1)
        guard to != from else { return }
        let shelf = bookshelf.shelves.remove(at: from)
        bookshelf.shelves.insert(shelf, at: to)
        for i in bookshelf.shelves.indices { saveShelf(at: i) }
    }

    /// Whether a shelf can be deleted, and where its books would go. Drives the confirmation prompt.
    enum ShelfDeletion: Equatable {
        /// `moveTo` is nil when the shelf is empty.
        case allowed(moveTo: Shelf?)
        /// A bookcase keeps at least one shelf.
        case lastShelf
        /// The shelf has books, and every other shelf is locked so none can take them.
        case noShelfForBooks
    }

    func shelfDeletion(_ shelfId: String) -> ShelfDeletion? {
        guard let shelf = bookshelf.shelves.first(where: { $0.id == shelfId }) else { return nil }
        let others = bookshelf.shelves.filter { $0.id != shelfId }
        if others.isEmpty { return .lastShelf }
        if shelf.bookIds.isEmpty { return .allowed(moveTo: nil) }
        // Books go to the first remaining shelf that can take them.
        guard let target = others.first(where: { !$0.isLocked }) else { return .noShelfForBooks }
        return .allowed(moveTo: target)
    }

    /// Deletes a shelf, moving its books to the end of the first remaining unlocked shelf so none are lost.
    /// Returns false, changing nothing, when `shelfDeletion` doesn't allow it.
    @discardableResult
    func deleteShelf(_ shelfId: String) -> Bool {
        guard case .allowed(let target) = shelfDeletion(shelfId),
              let index = bookshelf.shelves.firstIndex(where: { $0.id == shelfId }) else { return false }
        let shelf = bookshelf.shelves[index]
        var moving: [String] = []
        if let target, let targetIndex = bookshelf.shelves.firstIndex(where: { $0.id == target.id }) {
            moving = shelf.bookIds.filter { !bookshelf.shelves[targetIndex].bookIds.contains($0) }
            bookshelf.shelves[targetIndex].bookIds += moving
            // Saved before the delete, so the books are never on no shelf at all.
            saveShelfBooks(at: targetIndex)
        }
        remember(.shelf(shelf, index: index, movedTo: target?.id, movedBookIds: moving))
        bookshelf.shelves.remove(at: index)
        save(.deleteShelf(id: shelfId))
        for i in index..<bookshelf.shelves.count { saveShelf(at: i) }
        return true
    }

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
        guard let book = book(withId: bookId) else { return }
        remember(.book(
            book, meta: meta(for: bookId),
            shelves: bookshelf.shelves.compactMap { shelf in shelf.bookIds.firstIndex(of: bookId).map { Placement(id: shelf.id, index: $0) } },
            lists: lists.compactMap { list in list.bookIds.firstIndex(of: bookId).map { Placement(id: list.id, index: $0) } }
        ))
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

    // MARK: Undo

    static let maxUndo = 10

    /// Where an item sat in a shelf or list.
    struct Placement: Equatable {
        let id: String
        let index: Int
    }

    struct Deletion: Identifiable, Equatable {
        enum Kind: Equatable {
            /// `movedBookIds` are the books that went to `movedTo` and weren't already there.
            case shelf(Shelf, index: Int, movedTo: String?, movedBookIds: [String])
            case book(Book, meta: BookMeta?, shelves: [Placement], lists: [Placement])
        }

        let id = UUID()
        let kind: Kind

        var name: String {
            switch kind {
            case .shelf(let shelf, _, _, _): shelf.name
            case .book(let book, _, _, _): book.title
            }
        }
    }

    private func remember(_ kind: Deletion.Kind) {
        undoStack.append(Deletion(kind: kind))
        if undoStack.count > Self.maxUndo { undoStack.removeFirst(undoStack.count - Self.maxUndo) }
    }

    /// Restores the most recent deletion. Returns what was restored.
    @discardableResult
    func undoLastDeletion() -> Deletion? {
        guard let deletion = undoStack.popLast() else { return nil }
        switch deletion.kind {
        case .shelf(let shelf, let index, let movedTo, let movedBookIds):
            restoreShelf(shelf, at: index, movedTo: movedTo, movedBookIds: movedBookIds)
        case .book(let book, let meta, let shelves, let lists):
            restoreBook(book, meta: meta, shelves: shelves, lists: lists)
        }
        return deletion
    }

    private func restoreShelf(_ shelf: Shelf, at index: Int, movedTo: String?, movedBookIds: [String]) {
        guard !bookshelf.shelves.contains(where: { $0.id == shelf.id }) else { return }
        // Take back the books that were moved off it, then put it back where it was.
        if let targetIndex = bookshelf.shelves.firstIndex(where: { $0.id == movedTo }) {
            bookshelf.shelves[targetIndex].bookIds.removeAll { movedBookIds.contains($0) }
            saveShelfBooks(at: targetIndex)
        }
        var restored = shelf
        restored.bookIds = shelf.bookIds.filter { book(withId: $0) != nil }
        let index = min(index, bookshelf.shelves.count)
        bookshelf.shelves.insert(restored, at: index)
        for i in index..<bookshelf.shelves.count { saveShelf(at: i) }
        saveShelfBooks(at: index)
    }

    private func restoreBook(_ book: Book, meta: BookMeta?, shelves: [Placement], lists placements: [Placement]) {
        guard self.book(withId: book.id) == nil else { return }
        books.append(book)
        save(.saveBook(book))
        if let meta {
            metas.append(meta)
            save(.saveMeta(meta))
        }
        var placed = false
        for placement in shelves {
            guard let i = bookshelf.shelves.firstIndex(where: { $0.id == placement.id }) else { continue }
            bookshelf.shelves[i].bookIds.insert(book.id, at: min(placement.index, bookshelf.shelves[i].bookIds.count))
            saveShelfBooks(at: i)
            placed = true
        }
        // Its shelves are gone: put it on the default shelf so it's still visible.
        if !placed, !shelves.isEmpty, let i = bookshelf.shelves.firstIndex(where: { $0.id == defaultShelfId }) {
            bookshelf.shelves[i].bookIds.insert(book.id, at: 0)
            saveShelfBooks(at: i)
        }
        for placement in placements {
            guard let i = lists.firstIndex(where: { $0.id == placement.id }) else { continue }
            lists[i].bookIds.insert(book.id, at: min(placement.index, lists[i].bookIds.count))
            saveListBooks(at: i)
        }
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
