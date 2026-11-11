import Foundation
import Testing
@testable import Bookplate

@MainActor
struct MultipleLibrariesTests {
    private let me = UUID()
    private let friend = UUID()

    private func library(_ name: String, position: Int = 0, owner: UUID? = nil, access: LibraryInfo.Access = .owner) -> LibraryInfo {
        LibraryInfo(id: UUID(), name: name, ownerId: owner ?? me, ownerName: "Me", position: position, access: access)
    }

    private func session(_ libraries: [LibraryInfo], defaults: UserDefaults? = nil) -> (LibrarySession, InMemoryLibraryDirectory) {
        let directory = InMemoryLibraryDirectory(userId: me, libraries: libraries)
        let defaults = defaults ?? UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return (LibrarySession(userId: me, ownerName: "Me", directory: directory, defaults: defaults), directory)
    }

    // MARK: Starting

    @Test func newAccountGetsMyLibrary() async throws {
        let (session, directory) = session([])
        try await session.start()
        #expect(session.owned.map(\.name) == ["My Library"])
        #expect(session.current?.name == "My Library")
        #expect(session.current?.ownerName == "Me")
        #expect(directory.items.count == 1)
    }

    @Test func opensTheFirstOwnedLibraryByDefault() async throws {
        let shared = library("Maya's", owner: friend, access: .view)
        let (session, _) = session([shared, library("Office", position: 1), library("Home", position: 0)])
        try await session.start()
        #expect(session.libraries.map(\.name) == ["Home", "Office", "Maya's"])
        #expect(session.current?.name == "Home")
        #expect(session.shared.map(\.name) == ["Maya's"])
    }

    @Test func remembersTheLastOpenedLibrary() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let home = library("Home"), office = library("Office", position: 1)
        let (first, _) = session([home, office], defaults: defaults)
        try await first.start()
        first.select(office.id)

        let (second, _) = session([home, office], defaults: defaults)
        try await second.start()
        #expect(second.current?.id == office.id)
    }

    @Test func forgetsARememberedLibraryThatIsGone() async throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set(UUID().uuidString, forKey: "selectedLibrary.\(me.uuidString.lowercased())")
        let home = library("Home")
        let (session, _) = session([home], defaults: defaults)
        try await session.start()
        #expect(session.current?.id == home.id)
    }

    @Test func startFailsWhenTheListCantLoad() async {
        let (session, directory) = session([])
        directory.error = .network
        await #expect(throws: BookServiceError.network) { try await session.start() }
    }

    // MARK: Creating, renaming, deleting

    @Test func createAddsAtTheEndAndOpensIt() async throws {
        let (session, _) = session([library("Home")])
        try await session.start()
        let office = try #require(try await session.create(named: "  Office  "))
        #expect(office.name == "Office")
        #expect(office.position == 1)
        #expect(session.current?.id == office.id)
        #expect(session.owned.map(\.name) == ["Home", "Office"])
    }

    @Test func nameRules() async throws {
        let (session, _) = session([library("Home"), library("Maya's", owner: friend, access: .view)])
        try await session.start()
        #expect(session.nameProblem("  ") == .blank)
        #expect(session.nameProblem(String(repeating: "x", count: 41)) == .tooLong)
        #expect(session.nameProblem("home") == .duplicate)
        #expect(session.nameProblem("Maya's") == nil)   // only your own libraries clash
        #expect(session.nameProblem("Home", excluding: session.owned[0].id) == nil)
        #expect(try await session.create(named: "HOME") == nil)
    }

    @Test func renameUpdatesTheList() async throws {
        let home = library("Home")
        let (session, directory) = session([home])
        try await session.start()
        try await session.rename(home.id, to: " Cabin ")
        #expect(session.current?.name == "Cabin")
        #expect(directory.items.first?.name == "Cabin")
    }

    @Test func deleteKeepsAtLeastOneLibrary() async throws {
        let home = library("Home"), office = library("Office", position: 1)
        let (session, directory) = session([home, office])
        try await session.start()
        session.select(office.id)
        #expect(session.canDelete(office.id))
        try await session.delete(office.id)
        #expect(session.owned.map(\.name) == ["Home"])
        #expect(session.current?.id == home.id)
        #expect(!session.canDelete(home.id))
        try await session.delete(home.id)
        #expect(directory.items.count == 1)
    }

    @Test func cantDeleteSomeoneElsesLibrary() async throws {
        let shared = library("Maya's", owner: friend, access: .view)
        let (session, _) = session([library("Home"), library("Office", position: 1), shared])
        try await session.start()
        #expect(!session.canDelete(shared.id))
    }

    // MARK: Library info

    @Test func sharedDetailText() {
        #expect(LibrariesView.detail(library("Home")) == nil)
        var shared = library("Books", owner: friend, access: .view)
        shared.ownerName = "Maya"
        #expect(LibrariesView.detail(shared) == "Shared by Maya · View only")
        shared.access = .edit
        #expect(LibrariesView.detail(shared) == "Shared by Maya · Can edit")
    }

    @Test func libraryRowDecodesAndKnowsTheOwner() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","name":"Home","owner_id":"\#(me.uuidString)","owner_name":"Me","position":2}"#
        let row = try JSONDecoder().decode(LibraryRow.self, from: Data(json.utf8))
        #expect(row.info(for: me).access == .owner)
        #expect(row.info(for: friend).access == .view)
        #expect(row.info(for: friend, access: .edit).canEdit)
    }

    // MARK: Store and saving

    @Test func loadedStoreTakesTheLibraryName() async throws {
        let home = library("Home")
        let repo = InMemoryLibraryRepository()
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: me, sync: sync, localFiles: nil,
                                        coverLookup: NoCoverLookup(), library: home)
        #expect(store.bookshelf.name == "Home")
        #expect(store.library == home)
        var cabin = home
        cabin.name = "Cabin"
        store.libraryUpdated(cabin)
        #expect(store.bookshelf.name == "Cabin")
        #expect(store.library?.name == "Cabin")
        store.libraryUpdated(library("Elsewhere"))
        #expect(store.bookshelf.name == "Cabin")
    }

    @Test func nameLengthCountsCodePointsLikeTheDatabase() {
        let flags = String(repeating: "\u{1F1EF}\u{1F1F5}", count: 15) // 15 flags = 30 code points
        #expect(LibraryInfo.nameProblem(flags, among: []) == nil)
        #expect(LibraryInfo.nameProblem(flags + "\u{1F1EF}\u{1F1F5}" + "abcdefghi", among: []) == .tooLong)
    }

    @Test func scopedRowsCarryTheLibraryAndOwner() throws {
        let libraryId = UUID()
        let book = Book(id: "b1", title: "T", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil)
        let data = try JSONEncoder().encode(Scoped(row: BookRow(book), libraryId: libraryId, ownerId: friend))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["id"] as? String == "b1")
        #expect(object["library_id"] as? String == libraryId.uuidString)
        #expect(object["user_id"] as? String == friend.uuidString)
    }

    @Test func pendingChangesAreKeptPerLibrary() throws {
        let user = UUID()
        let a = try PendingChangesFile.forLibrary(UUID(), user: user)
        let b = try PendingChangesFile.forLibrary(UUID(), user: user)
        defer { a.save([]); b.save([]) }
        a.save([.deleteBook(id: "x")])
        #expect(a.load() == [.deleteBook(id: "x")])
        #expect(b.load().isEmpty)
        #expect(a.fileURL != (try PendingChangesFile.forUser(user)).fileURL)
    }
}
