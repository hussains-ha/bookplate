import Foundation
import Supabase

/// Everything in a user's library, as loaded at sign-in.
struct LibrarySnapshot: Equatable {
    var books: [Book] = []
    var metas: [BookMeta] = []
    /// In bookcase order, each with its books in shelf order.
    var shelves: [Shelf] = []
    var lists: [BookList] = []
}

/// One saved change. Changes are applied in the order they were made, so a book is
/// always saved before the details and shelf entries that refer to it.
enum LibraryChange: Codable, Equatable {
    case saveBook(Book)
    /// Also removes the book's details and its shelf and list entries.
    case deleteBook(id: String)
    /// Custom cover and note photos are not saved here: covers use `uploadCover`/`deleteCover`,
    /// note photos stay on the device.
    case saveMeta(BookMeta)
    /// Name, position and lock. The shelf's books are saved with `setShelfBooks`.
    case saveShelf(Shelf, position: Int)
    /// The database removes the shelf's book entries with it; the books themselves stay.
    case deleteShelf(id: String)
    case setShelfBooks(shelfId: String, bookIds: [String])
    case saveList(BookList, position: Int)
    case setListBooks(listId: String, bookIds: [String])
    /// Uploads the custom cover saved on this device as `fileName` (in the images folder) and records it.
    /// If the file is gone (replaced since), there's nothing to upload and the change is skipped.
    case uploadCover(bookId: String, fileName: String)
    /// Deletes the book's stored custom cover.
    case deleteCover(bookId: String)
}

/// Loads and saves the signed-in user's library.
/// `SupabaseLibraryRepository` is the real one; `InMemoryLibraryRepository` is for tests.
protocol LibraryRepository {
    func loadLibrary() async throws(BookServiceError) -> LibrarySnapshot
    func apply(_ change: LibraryChange) async throws(BookServiceError)
    /// Books whose title matches, ignoring case. Used for the duplicate check.
    func books(titled title: String) async throws(BookServiceError) -> [Book]
}

// MARK: Rows

/// A `book_meta` row. Dates use the Supabase coders (ISO 8601).
struct BookMetaRow: Codable, Equatable {
    var bookId: String
    var status: String
    var rating: Int?
    var notes: String?
    var tags: [String]
    var addedAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    /// Read only: set by `uploadCover`/`deleteCover`, never by a details save.
    var customCover: String?

    enum CodingKeys: String, CodingKey {
        case status, rating, notes, tags
        case customCover = "custom_cover"
        case bookId = "book_id"
        case addedAt = "added_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    init(_ meta: BookMeta) {
        bookId = meta.bookId
        status = meta.status
        rating = meta.rating
        notes = meta.notes
        tags = meta.tags
        addedAt = meta.addedDate
        startedAt = meta.startedDate
        finishedAt = meta.finishedDate
    }

    /// Writes every column, including nil ones: an upsert only updates the columns it's sent,
    /// so leaving out a cleared rating or note would keep the old value on the server.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookId, forKey: .bookId)
        try container.encode(status, forKey: .status)
        try container.encode(rating, forKey: .rating)
        try container.encode(notes, forKey: .notes)
        try container.encode(tags, forKey: .tags)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(finishedAt, forKey: .finishedAt)
    }

    var meta: BookMeta {
        BookMeta(bookId: bookId, status: status, rating: rating, notes: notes, notePhotos: [], tags: tags,
                 customCover: customCover.flatMap(CustomCoverPath.url(columnValue:)),
                 addedDate: addedAt, startedDate: startedAt, finishedDate: finishedAt)
    }
}

/// A `shelves` or `lists` row.
struct CollectionRow: Codable, Equatable {
    var id: String
    var name: String
    var position: Int
    /// Shelves only.
    var isLocked: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case isLocked = "is_locked"
    }
}

/// A `shelf_books` or `list_books` row.
struct MembershipRow: Codable, Equatable {
    var collectionId: String
    var bookId: String
    var position: Int

    /// `shelf_id` or `list_id`.
    let idColumn: String

    init(collectionId: String, bookId: String, position: Int, idColumn: String) {
        self.collectionId = collectionId
        self.bookId = bookId
        self.position = position
        self.idColumn = idColumn
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        idColumn = container.contains(Key(stringValue: "shelf_id")) ? "shelf_id" : "list_id"
        collectionId = try container.decode(String.self, forKey: Key(stringValue: idColumn))
        bookId = try container.decode(String.self, forKey: Key(stringValue: "book_id"))
        position = try container.decode(Int.self, forKey: Key(stringValue: "position"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(collectionId, forKey: Key(stringValue: idColumn))
        try container.encode(bookId, forKey: Key(stringValue: "book_id"))
        try container.encode(position, forKey: Key(stringValue: "position"))
    }
}

extension LibrarySnapshot {
    /// Builds a snapshot from table rows. Membership rows pointing at unknown books are skipped.
    init(books: [BookRow], metas: [BookMetaRow], shelves: [CollectionRow], shelfBooks: [MembershipRow],
         lists: [CollectionRow], listBooks: [MembershipRow]) {
        self.books = books.map(\.book)
        self.metas = metas.map(\.meta)
        let known = Set(self.books.map(\.id))
        func ordered(_ rows: [MembershipRow], in id: String) -> [String] {
            rows.filter { $0.collectionId == id && known.contains($0.bookId) }
                .sorted { $0.position < $1.position }
                .map(\.bookId)
        }
        // Ties (e.g. two devices adding a shelf at once) break by id, so the order is the same every launch.
        func inOrder(_ a: CollectionRow, _ b: CollectionRow) -> Bool { (a.position, a.id) < (b.position, b.id) }
        self.shelves = shelves.sorted(by: inOrder).map {
            Shelf(id: $0.id, name: $0.name, bookIds: ordered(shelfBooks, in: $0.id), isLocked: $0.isLocked ?? false)
        }
        self.lists = lists.sorted(by: inOrder).map {
            BookList(id: $0.id, name: $0.name, bookIds: ordered(listBooks, in: $0.id))
        }
    }
}

// MARK: Supabase

struct SupabaseLibraryRepository: LibraryRepository {
    /// The account this library belongs to. Requests fail with `.notSignedIn` if a different
    /// account is signed in, so one user's queued changes never land in another's library.
    let userId: UUID
    var client: SupabaseClient = SupabaseService.client
    var covers: CoverStorage?
    /// Where `uploadCover` finds the picked photo.
    var imagesFolder: () throws -> URL = { try LocalImageStorage.folder() }

    private var coverStorage: CoverStorage { covers ?? SupabaseCoverStorage(client: client) }

    func loadLibrary() async throws(BookServiceError) -> LibrarySnapshot {
        try await run {
            async let books: [BookRow] = client.from("books").select().order("created_at").execute().value
            async let metas: [BookMetaRow] = client.from("book_meta").select().execute().value
            async let shelves: [CollectionRow] = client.from("shelves").select("id,name,position,is_locked").execute().value
            async let shelfBooks: [MembershipRow] = client.from("shelf_books").select("shelf_id,book_id,position").execute().value
            async let lists: [CollectionRow] = client.from("lists").select("id,name,position").execute().value
            async let listBooks: [MembershipRow] = client.from("list_books").select("list_id,book_id,position").execute().value
            return try await LibrarySnapshot(books: books, metas: metas, shelves: shelves, shelfBooks: shelfBooks,
                                             lists: lists, listBooks: listBooks)
        }
    }

    func apply(_ change: LibraryChange) async throws(BookServiceError) {
        try await run {
            switch change {
            case .saveBook(let book):
                try await client.from("books")
                    .upsert(BookRow(book), onConflict: "user_id,id", returning: .minimal).execute()
            case .deleteBook(let id):
                try await client.from("books").delete().eq("id", value: id).execute()
                // Best effort: a leftover cover file is harmless and unreachable by others.
                try? await coverStorage.remove(path: CustomCoverPath.objectPath(userId: userId, bookId: id))
            case .uploadCover(let bookId, let fileName):
                guard let data = try? Data(contentsOf: imagesFolder().appendingPathComponent(fileName)) else { return }
                try await coverStorage.upload(data, path: CustomCoverPath.objectPath(userId: userId, bookId: bookId))
                let value = CustomCoverPath.columnValue(userId: userId, bookId: bookId,
                                                        version: CustomCoverPath.version(fileName: fileName))
                try await client.from("book_meta").update(CustomCoverUpdate(customCover: value))
                    .eq("book_id", value: bookId).execute()
            case .deleteCover(let bookId):
                try await coverStorage.remove(path: CustomCoverPath.objectPath(userId: userId, bookId: bookId))
                try await client.from("book_meta").update(CustomCoverUpdate(customCover: nil))
                    .eq("book_id", value: bookId).execute()
            case .saveMeta(let meta):
                try await client.from("book_meta")
                    .upsert(BookMetaRow(meta), onConflict: "user_id,book_id", returning: .minimal).execute()
            case .saveShelf(let shelf, let position):
                let row = CollectionRow(id: shelf.id, name: shelf.name, position: position, isLocked: shelf.isLocked)
                try await client.from("shelves").upsert(row, onConflict: "user_id,id", returning: .minimal).execute()
            case .deleteShelf(let id):
                try await client.from("shelves").delete().eq("id", value: id).execute()
            case .setShelfBooks(let shelfId, let bookIds):
                try await client.rpc("set_shelf_books", params: SetBooksParams(id: shelfId, bookIds: bookIds, idKey: "p_shelf_id")).execute()
            case .saveList(let list, let position):
                let row = CollectionRow(id: list.id, name: list.name, position: position)
                try await client.from("lists").upsert(row, onConflict: "user_id,id", returning: .minimal).execute()
            case .setListBooks(let listId, let bookIds):
                try await client.rpc("set_list_books", params: SetBooksParams(id: listId, bookIds: bookIds, idKey: "p_list_id")).execute()
            }
        }
    }

    func books(titled title: String) async throws(BookServiceError) -> [Book] {
        try await run {
            let rows: [BookRow] = try await client.from("books").select()
                .ilike("title", pattern: Self.escapeLike(title)).execute().value
            return rows.map(\.book)
        }
    }

    /// Escapes LIKE wildcards so the title matches literally.
    static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// Writes `custom_cover` even when nil, so clearing it reaches the server.
    private struct CustomCoverUpdate: Encodable {
        let customCover: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(customCover, forKey: .customCover)
        }

        enum CodingKeys: String, CodingKey { case customCover = "custom_cover" }
    }

    private struct SetBooksParams: Encodable {
        let id: String
        let bookIds: [String]
        let idKey: String

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AnyKey.self)
            try container.encode(id, forKey: AnyKey(idKey))
            try container.encode(bookIds, forKey: AnyKey("p_book_ids"))
        }

        private struct AnyKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(_ string: String) { stringValue = string }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
    }

    private func run<T>(_ request: () async throws -> T) async throws(BookServiceError) -> T {
        try await BookService.requireSession(client)
        guard client.auth.currentUser?.id == userId else { throw .notSignedIn }
        do {
            return try await request()
        } catch {
            throw BookService.failure(from: error)
        }
    }
}

// MARK: Applying changes

extension LibrarySnapshot {
    /// Applies a change the way the database does, including cascading deletes.
    /// Throws `.rejected` when the change refers to a book, shelf or list that doesn't exist.
    mutating func apply(_ change: LibraryChange) throws(BookServiceError) {
        switch change {
        case .saveBook(let book):
            Self.upsert(book, into: &books, id: \.id)
        case .deleteBook(let id):
            books.removeAll { $0.id == id }
            metas.removeAll { $0.bookId == id }
            for i in shelves.indices { shelves[i].bookIds.removeAll { $0 == id } }
            for i in lists.indices { lists[i].bookIds.removeAll { $0 == id } }
        case .saveMeta(let meta):
            try requireBook(meta.bookId)
            var saved = meta
            // Like the database: a details save doesn't touch the stored cover.
            saved.customCover = metas.first { $0.bookId == meta.bookId }?.customCover
            saved.notePhotos = []
            Self.upsert(saved, into: &metas, id: \.bookId)
        case .uploadCover(let bookId, _):
            // The stored path depends on the user; the device shows its local copy meanwhile (`LocalBookFiles`).
            try requireBook(bookId)
        case .deleteCover(let bookId):
            try requireBook(bookId)
            if let i = metas.firstIndex(where: { $0.bookId == bookId }) { metas[i].customCover = nil }
        case .saveShelf(let shelf, let position):
            let existing = shelves.first { $0.id == shelf.id }?.bookIds ?? []
            shelves.removeAll { $0.id == shelf.id }
            var saved = shelf
            saved.bookIds = existing
            shelves.insert(saved, at: min(position, shelves.count))
        case .deleteShelf(let id):
            shelves.removeAll { $0.id == id }
        case .setShelfBooks(let shelfId, let bookIds):
            guard let i = shelves.firstIndex(where: { $0.id == shelfId }) else { throw .rejected("No shelf \(shelfId)") }
            // Like `set_shelf_books`: unknown books are skipped.
            shelves[i].bookIds = bookIds.filter(hasBook)
        case .saveList(let list, let position):
            let existing = lists.first { $0.id == list.id }?.bookIds ?? []
            lists.removeAll { $0.id == list.id }
            var saved = list
            saved.bookIds = existing
            lists.insert(saved, at: min(position, lists.count))
        case .setListBooks(let listId, let bookIds):
            guard let i = lists.firstIndex(where: { $0.id == listId }) else { throw .rejected("No list \(listId)") }
            lists[i].bookIds = bookIds.filter(hasBook)
        }
    }

    /// Replays changes that were never confirmed by the server on top of a freshly loaded library,
    /// so the app shows them while they're sent again.
    ///
    /// A book the server doesn't have is only brought back if it was *added* on this device (its
    /// queued changes include its first details). Otherwise it was deleted elsewhere, and changes
    /// to it (a cover lookup, an edit) are dropped rather than resurrecting it.
    mutating func replay(_ changes: [LibraryChange]) -> (missing: [Book], toSend: [LibraryChange]) {
        let known = Set(books.map(\.id))
        let addedHere = Set(changes.compactMap { change -> String? in
            if case .saveMeta(let meta) = change { meta.bookId } else { nil }
        }).subtracting(known)
        var missing: [Book] = []
        var toSend: [LibraryChange] = []
        for change in changes {
            switch change {
            case .saveBook(let book) where !known.contains(book.id):
                guard addedHere.contains(book.id) else { continue }
                if !missing.contains(where: { $0.id == book.id }) { missing.append(book) }
            case .saveMeta(let meta) where !known.contains(meta.bookId) && !addedHere.contains(meta.bookId):
                continue
            case .uploadCover(let bookId, _) where !known.contains(bookId) && !addedHere.contains(bookId),
                 .deleteCover(let bookId) where !known.contains(bookId) && !addedHere.contains(bookId):
                continue
            default:
                break
            }
            toSend.append(change)
            try? apply(change)
        }
        // A book added and then deleted before either was saved isn't missing.
        return (missing.filter { book in books.contains { $0.id == book.id } }, toSend)
    }

    private func hasBook(_ id: String) -> Bool {
        books.contains { $0.id == id }
    }

    private func requireBook(_ id: String) throws(BookServiceError) {
        guard books.contains(where: { $0.id == id }) else { throw .rejected("No book \(id)") }
    }

    private static func upsert<T>(_ item: T, into items: inout [T], id: KeyPath<T, String>) {
        if let i = items.firstIndex(where: { $0[keyPath: id] == item[keyPath: id] }) {
            items[i] = item
        } else {
            items.append(item)
        }
    }
}

// MARK: In memory

/// Behaves like the database (including cascading deletes), for tests and previews.
final class InMemoryLibraryRepository: LibraryRepository {
    private(set) var snapshot: LibrarySnapshot
    private(set) var applied: [LibraryChange] = []
    /// When set, `books(titled:)` throws it (to test the offline fallback).
    var searchError: BookServiceError?

    init(_ snapshot: LibrarySnapshot = LibrarySnapshot()) {
        self.snapshot = snapshot
    }

    func loadLibrary() async throws(BookServiceError) -> LibrarySnapshot { snapshot }

    /// When set, cover changes go through it, like the real repository's storage bucket.
    var covers: CoverStorage?

    func apply(_ change: LibraryChange) async throws(BookServiceError) {
        applied.append(change)
        if let covers {
            do {
                switch change {
                case .uploadCover(let bookId, let fileName): try await covers.upload(Data(fileName.utf8), path: bookId)
                case .deleteCover(let bookId): try await covers.remove(path: bookId)
                case .deleteBook(let bookId): try? await covers.remove(path: bookId)
                default: break
                }
            } catch {
                throw BookService.failure(from: error)
            }
        }
        try snapshot.apply(change)
    }

    func books(titled title: String) async throws(BookServiceError) -> [Book] {
        if let searchError { throw searchError }
        return snapshot.books.filter { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }
}
