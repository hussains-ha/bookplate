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
enum LibraryChange: Equatable {
    case saveBook(Book)
    /// Also removes the book's details and its shelf and list entries.
    case deleteBook(id: String)
    /// Custom cover and note photos are not saved; they stay on the device until #36.
    case saveMeta(BookMeta)
    /// Name, position and lock. The shelf's books are saved with `setShelfBooks`.
    case saveShelf(Shelf, position: Int)
    case setShelfBooks(shelfId: String, bookIds: [String])
    case saveList(BookList, position: Int)
    case setListBooks(listId: String, bookIds: [String])
}

/// Loads and saves the signed-in user's library.
/// `SupabaseLibraryRepository` is the real one; `InMemoryLibraryRepository` is for tests.
protocol LibraryRepository {
    func loadLibrary() async throws(BookServiceError) -> LibrarySnapshot
    func apply(_ change: LibraryChange) async throws(BookServiceError)
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

    enum CodingKeys: String, CodingKey {
        case status, rating, notes, tags
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

    var meta: BookMeta {
        BookMeta(bookId: bookId, status: status, rating: rating, notes: notes, notePhotos: [], tags: tags,
                 customCover: nil, addedDate: addedAt, startedDate: startedAt, finishedDate: finishedAt)
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
        self.shelves = shelves.sorted { $0.position < $1.position }.map {
            Shelf(id: $0.id, name: $0.name, bookIds: ordered(shelfBooks, in: $0.id), isLocked: $0.isLocked ?? false)
        }
        self.lists = lists.sorted { $0.position < $1.position }.map {
            BookList(id: $0.id, name: $0.name, bookIds: ordered(listBooks, in: $0.id))
        }
    }
}

// MARK: Supabase

struct SupabaseLibraryRepository: LibraryRepository {
    var client: SupabaseClient = SupabaseService.client

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
            case .saveMeta(let meta):
                try await client.from("book_meta")
                    .upsert(BookMetaRow(meta), onConflict: "user_id,book_id", returning: .minimal).execute()
            case .saveShelf(let shelf, let position):
                let row = CollectionRow(id: shelf.id, name: shelf.name, position: position, isLocked: shelf.isLocked)
                try await client.from("shelves").upsert(row, onConflict: "user_id,id", returning: .minimal).execute()
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
        guard client.auth.currentSession != nil else { throw .notSignedIn }
        do {
            return try await request()
        } catch {
            throw BookService.failure(from: error)
        }
    }
}

// MARK: In memory

/// Behaves like the database (including cascading deletes), for tests and previews.
final class InMemoryLibraryRepository: LibraryRepository {
    private(set) var snapshot: LibrarySnapshot
    private(set) var applied: [LibraryChange] = []

    init(_ snapshot: LibrarySnapshot = LibrarySnapshot()) {
        self.snapshot = snapshot
    }

    func loadLibrary() async throws(BookServiceError) -> LibrarySnapshot { snapshot }

    func apply(_ change: LibraryChange) async throws(BookServiceError) {
        applied.append(change)
        switch change {
        case .saveBook(let book):
            upsert(book, into: &snapshot.books, id: \.id)
        case .deleteBook(let id):
            snapshot.books.removeAll { $0.id == id }
            snapshot.metas.removeAll { $0.bookId == id }
            for i in snapshot.shelves.indices { snapshot.shelves[i].bookIds.removeAll { $0 == id } }
            for i in snapshot.lists.indices { snapshot.lists[i].bookIds.removeAll { $0 == id } }
        case .saveMeta(let meta):
            try requireBook(meta.bookId)
            var saved = meta
            saved.customCover = nil
            saved.notePhotos = []
            upsert(saved, into: &snapshot.metas, id: \.bookId)
        case .saveShelf(let shelf, let position):
            let existing = snapshot.shelves.first { $0.id == shelf.id }?.bookIds ?? []
            snapshot.shelves.removeAll { $0.id == shelf.id }
            var saved = shelf
            saved.bookIds = existing
            snapshot.shelves.insert(saved, at: min(position, snapshot.shelves.count))
        case .setShelfBooks(let shelfId, let bookIds):
            guard let i = snapshot.shelves.firstIndex(where: { $0.id == shelfId }) else { throw .rejected("No shelf \(shelfId)") }
            for id in bookIds { try requireBook(id) }
            snapshot.shelves[i].bookIds = bookIds
        case .saveList(let list, let position):
            let existing = snapshot.lists.first { $0.id == list.id }?.bookIds ?? []
            snapshot.lists.removeAll { $0.id == list.id }
            var saved = list
            saved.bookIds = existing
            snapshot.lists.insert(saved, at: min(position, snapshot.lists.count))
        case .setListBooks(let listId, let bookIds):
            guard let i = snapshot.lists.firstIndex(where: { $0.id == listId }) else { throw .rejected("No list \(listId)") }
            for id in bookIds { try requireBook(id) }
            snapshot.lists[i].bookIds = bookIds
        }
    }

    private func requireBook(_ id: String) throws(BookServiceError) {
        guard snapshot.books.contains(where: { $0.id == id }) else { throw .rejected("No book \(id)") }
    }

    private func upsert<T>(_ item: T, into items: inout [T], id: KeyPath<T, String>) {
        if let i = items.firstIndex(where: { $0[keyPath: id] == item[keyPath: id] }) {
            items[i] = item
        } else {
            items.append(item)
        }
    }
}
