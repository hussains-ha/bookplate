import Foundation
import Testing
@testable import Bookplate

/// Records storage calls; fails the next `failures` calls with a network error.
final class MockCoverStorage: CoverStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var _uploads: [String] = []
    private var _removals: [String] = []
    private var _failures = 0
    var files: [String: Data] = [:]

    init(failures: Int = 0) { _failures = failures }

    var uploads: [String] { lock.withLock { _uploads } }
    var removals: [String] { lock.withLock { _removals } }

    private func failIfNeeded() throws {
        try lock.withLock {
            if _failures > 0 { _failures -= 1; throw URLError(.notConnectedToInternet) }
        }
    }

    func upload(_ data: Data, path: String) async throws {
        try failIfNeeded()
        lock.withLock { _uploads.append(path) }
    }

    func remove(path: String) async throws {
        try failIfNeeded()
        lock.withLock { _removals.append(path) }
    }

    func download(path: String) async throws -> Data {
        try failIfNeeded()
        guard let data = lock.withLock({ files[path] }) else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

struct CustomCoverPathTests {
    private let user = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!

    @Test func pathIsUserFolderAndBookId() {
        #expect(CustomCoverPath.objectPath(userId: user, bookId: "book-1")
            == "6f9619ff-8b86-d011-b42d-00cf4fc964ff/book-1.jpg")
    }

    @Test func columnValueRoundTripsToTheObjectPath() throws {
        let value = CustomCoverPath.columnValue(userId: user, bookId: "book-1", version: "abc")
        #expect(value == "6f9619ff-8b86-d011-b42d-00cf4fc964ff/book-1.jpg?v=abc")
        let url = try #require(CustomCoverPath.url(columnValue: value))
        #expect(url.scheme == "bookplate-cover")
        #expect(CustomCoverPath.objectPath(from: url) == "6f9619ff-8b86-d011-b42d-00cf4fc964ff/book-1.jpg")
    }

    @Test func otherURLsAreNotStoredCovers() {
        #expect(CustomCoverPath.objectPath(from: URL(string: "https://covers.openlibrary.org/b/1.jpg")!) == nil)
        #expect(CustomCoverPath.objectPath(from: URL(fileURLWithPath: "/tmp/a.jpg")) == nil)
    }

    @Test func versionIsTheFileNameWithoutExtension() {
        #expect(CustomCoverPath.version(fileName: "1234-abcd.jpg") == "1234-abcd")
    }

    @Test func metaRowReadsTheStoredCover() throws {
        let json = #"{"book_id":"b","status":"want","tags":[],"added_at":"2026-11-10T00:00:00Z","custom_cover":"u/b.jpg?v=1"}"#
        let row = try JSONDecoder.supabaseTest.decode(BookMetaRow.self, from: Data(json.utf8))
        #expect(row.meta.customCover == URL(string: "bookplate-cover://covers/u/b.jpg?v=1"))
    }

    @Test func detailsSaveNeverWritesTheCoverColumn() throws {
        var meta = BookMeta.mocks[0]
        meta.customCover = URL(fileURLWithPath: "/tmp/x.jpg")
        let json = try #require(String(data: try JSONEncoder().encode(BookMetaRow(meta)), encoding: .utf8))
        #expect(!json.contains("custom_cover"))
    }
}

private extension JSONDecoder {
    static var supabaseTest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@MainActor
struct CoverStorageSyncTests {
    private func setup(storage: MockCoverStorage) throws -> (LibraryStore, LibrarySync, InMemoryLibraryRepository, URL) {
        let repo = InMemoryLibraryRepository()
        repo.covers = storage
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = LocalBookFiles(fileURL: folder.appendingPathComponent("local.json"), imagesFolder: folder)
        let sync = LibrarySync(repository: repo, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(LibrarySnapshot(), userId: UUID(), sync: sync, localFiles: files,
                                        coverLookup: NoCoverLookup())
        return (store, sync, repo, folder)
    }

    private func photo(in folder: URL, _ name: String = "\(UUID().uuidString).jpg") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("jpeg".utf8).write(to: url)
        return url
    }

    @Test func settingACoverUploadsIt() async throws {
        let storage = MockCoverStorage()
        let (store, sync, _, folder) = try setup(storage: storage)
        let book = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: nil))
        let cover = try photo(in: folder)
        store.setCustomCover(cover, for: book.id)
        #expect(store.meta(for: book.id)?.customCover == cover)   // shown right away from the local copy
        await sync.waitUntilIdle()
        #expect(storage.uploads == [book.id])
    }

    @Test func failedUploadKeepsTheLocalCopyAndRetries() async throws {
        let storage = MockCoverStorage(failures: 2)
        let (store, sync, repo, folder) = try setup(storage: storage)
        let book = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: nil))
        await sync.waitUntilIdle()
        let cover = try photo(in: folder)
        store.setCustomCover(cover, for: book.id)
        await sync.waitUntilIdle()
        #expect(storage.uploads == [book.id])
        #expect(repo.applied.filter { $0 == .uploadCover(bookId: book.id, fileName: cover.lastPathComponent) }.count == 3)
        #expect(store.meta(for: book.id)?.customCover == cover)
        #expect(FileManager.default.fileExists(atPath: cover.path))
    }

    @Test func removingTheCoverDeletesTheStoredFile() async throws {
        let storage = MockCoverStorage()
        let (store, sync, _, folder) = try setup(storage: storage)
        let book = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: nil))
        store.setCustomCover(try photo(in: folder), for: book.id)
        await sync.waitUntilIdle()
        store.setCustomCover(nil, for: book.id)
        await sync.waitUntilIdle()
        #expect(storage.removals == [book.id])
        #expect(store.meta(for: book.id)?.customCover == nil)
    }

    @Test func deletingTheBookDeletesTheStoredCover() async throws {
        let storage = MockCoverStorage()
        let (store, sync, _, folder) = try setup(storage: storage)
        let book = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: nil))
        store.setCustomCover(try photo(in: folder), for: book.id)
        await sync.waitUntilIdle()
        store.removeBook(book.id)
        await sync.waitUntilIdle()
        #expect(storage.removals == [book.id])
    }

    @Test func undoReuploadsALocalCover() async throws {
        let storage = MockCoverStorage()
        let (store, sync, _, folder) = try setup(storage: storage)
        let book = try #require(store.addBook(title: "Dune", author: "", pageCount: nil, shelfId: nil))
        let cover = try photo(in: folder)
        store.setCustomCover(cover, for: book.id)
        await sync.waitUntilIdle()
        store.removeBook(book.id)
        store.undoLastDeletion()
        await sync.waitUntilIdle()
        #expect(storage.uploads == [book.id, book.id])
        #expect(store.meta(for: book.id)?.customCover == cover)
    }

    @Test func latestCoverChoiceReplacesAQueuedOne() async throws {
        let storage = MockCoverStorage()
        let repo = InMemoryLibraryRepository()
        repo.covers = storage
        let book = Book(id: "b", title: "T", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil)
        try await repo.apply(.saveBook(book))
        // All enqueued before the worker runs, so the cover changes coalesce.
        let sync = LibrarySync(repository: repo, retryDelays: [.zero], sleep: { _ in })
        sync.enqueue(.saveBook(book))
        sync.enqueue(.uploadCover(bookId: "b", fileName: "1.jpg"))
        sync.enqueue(.uploadCover(bookId: "b", fileName: "2.jpg"))
        sync.enqueue(.deleteCover(bookId: "b"))
        await sync.waitUntilIdle()
        #expect(!repo.applied.contains(.uploadCover(bookId: "b", fileName: "1.jpg")))
        #expect(!repo.applied.contains(.uploadCover(bookId: "b", fileName: "2.jpg")))
        #expect(repo.applied.last == .deleteCover(bookId: "b"))
    }

    @Test func localFilesFallBackToTheStoredCoverWhenTheFileIsGone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = LocalBookFiles(fileURL: folder.appendingPathComponent("local.json"), imagesFolder: folder)
        let stored = URL(string: "bookplate-cover://covers/u/b.jpg?v=1")!
        var meta = BookMeta.mocks[0]
        meta.customCover = folder.appendingPathComponent("missing.jpg")
        files.save([meta])
        meta.customCover = stored
        #expect(files.apply(to: [meta]).first?.customCover == stored)

        // And a stored cover is never written down as a local file name.
        files.save([meta])
        #expect(files.load()[meta.bookId]?.customCover == nil)
    }

    @Test func loaderDownloadsStoredCoversThroughStorage() async throws {
        let storage = MockCoverStorage()
        storage.files["u/b.jpg"] = CoverImageLoaderTests.png(width: 20, height: 30)
        let loader = CoverImageLoader(storage: storage, cacheFolder: nil)
        let image = try await loader.image(for: URL(string: "bookplate-cover://covers/u/b.jpg?v=1")!, maxPixelSize: 30)
        #expect(image.height == 30)
    }
}
