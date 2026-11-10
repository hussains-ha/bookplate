import Foundation
import Testing
@testable import Bookplate

@MainActor
struct ListsTabTests {
    private func book(_ id: String, _ title: String, by author: String = "Anon") -> Book {
        Book(id: id, title: title, authors: [author], pageCount: nil, coverUrl: nil, isbn13: nil)
    }

    private var books: [Book] {
        [book("1", "Dune", by: "Frank Herbert"), book("2", "Educated", by: "Tara Westover"),
         book("3", "Sapiens", by: "Yuval Noah Harari")]
    }

    private func store(_ lists: [BookList]) -> LibraryStore {
        LibraryStore(books: books, metas: [],
                     bookshelf: Bookshelf(id: "b", name: "B", shelves: [], appearance: .classic),
                     lists: lists, coverLookup: NoCoverLookup())
    }

    private let club = BookList(id: "club", name: "Book Club", bookIds: ["1", "2"])
    private let later = BookList(id: "later", name: "Later", bookIds: ["3"])

    // MARK: Names

    @Test func listNameRules() {
        let store = store([club])
        #expect(store.listNameProblem("   ") == .blank)
        #expect(store.listNameProblem(String(repeating: "x", count: LibraryStore.maxListNameLength + 1)) == .tooLong)
        #expect(store.listNameProblem(" book club ") == .duplicate)
        #expect(store.listNameProblem("Summer") == nil)
    }

    @Test func addListTrimsTheNameAndAppends() throws {
        let store = store([club])
        let list = try #require(store.addList(named: "  Summer  "))
        #expect(list.name == "Summer")
        #expect(list.bookIds.isEmpty)
        #expect(list.id.hasPrefix("list-"))
        #expect(store.lists.map(\.name) == ["Book Club", "Summer"])
    }

    @Test func addListRefusesABadName() {
        let store = store([club])
        #expect(store.addList(named: "BOOK CLUB") == nil)
        #expect(store.addList(named: "") == nil)
        #expect(store.lists.count == 1)
    }

    // MARK: Deleting

    @Test func deleteListKeepsTheBooks() {
        let store = store([club, later])
        store.deleteList("club")
        #expect(store.lists == [later])
        #expect(store.books.count == 3)
    }

    @Test func deleteUnknownListDoesNothing() {
        let store = store([club])
        store.deleteList("nope")
        #expect(store.lists == [club])
    }

    @Test func removingABookFromAListKeepsItInTheLibrary() {
        let store = store([club])
        store.setBook("1", inList: "club", to: false)
        #expect(store.lists[0].bookIds == ["2"])
        #expect(store.book(withId: "1") != nil)
    }

    @Test func deleteSavesAndMovesLaterListsUp() async throws {
        let snapshot = LibrarySnapshot(books: books, lists: [club, later, BookList(id: "x", name: "X", bookIds: [])])
        let repo = InMemoryLibraryRepository(snapshot)
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        store.deleteList("club")
        await sync.waitUntilIdle()
        #expect(repo.applied.first == .deleteList(id: "club"))
        let reloaded = try await repo.loadLibrary()
        #expect(reloaded.lists.map(\.id) == ["later", "x"])
        #expect(reloaded.lists[0].bookIds == ["3"])
        #expect(reloaded.books.count == 3)
    }

    @Test func addedListIsSaved() async throws {
        let repo = InMemoryLibraryRepository(LibrarySnapshot(books: books))
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        let list = try #require(store.addList(named: "Summer"))
        store.setBook("2", inList: list.id, to: true)
        await sync.waitUntilIdle()
        let reloaded = try await repo.loadLibrary()
        #expect(reloaded.lists == [BookList(id: list.id, name: "Summer", bookIds: ["2"])])
    }

    @Test func deleteListChangeRoundTripsThroughCodable() throws {
        let change = LibraryChange.deleteList(id: "club")
        let decoded = try JSONDecoder().decode(LibraryChange.self, from: JSONEncoder().encode(change))
        #expect(decoded == change)
    }

    // MARK: Visible lists

    @Test func showsEveryListWithItsBooksInOrder() {
        let store = store([club, later, BookList(id: "empty", name: "Empty", bookIds: [])])
        let visible = store.visibleLists()
        #expect(visible.map(\.id) == ["club", "later", "empty"])
        #expect(visible[0].books.map(\.id) == ["1", "2"])
        #expect(visible[2].books.isEmpty)
    }

    @Test func skipsIdsWithNoBook() {
        let store = store([BookList(id: "l", name: "L", bookIds: ["1", "gone"])])
        #expect(store.visibleLists()[0].books.map(\.id) == ["1"])
    }

    @Test func searchByListNameShowsTheWholeList() {
        let store = store([club, later])
        let visible = store.visibleLists(matching: "club")
        #expect(visible.map(\.id) == ["club"])
        #expect(visible[0].books.map(\.id) == ["1", "2"])
    }

    @Test func searchByTitleOrAuthorShowsOnlyMatchingBooks() {
        let store = store([club, later])
        #expect(store.visibleLists(matching: "educ").map { $0.books.map(\.id) } == [["2"]])
        #expect(store.visibleLists(matching: "harari").map(\.id) == ["later"])
    }

    @Test func searchIgnoresCaseAndAccents() {
        let store = store([BookList(id: "c", name: "Café Reads", bookIds: ["1"])])
        #expect(store.visibleLists(matching: "CAFE").map(\.id) == ["c"])
    }

    @Test func searchWithNoMatchesIsEmpty() {
        let store = store([club, later])
        #expect(store.visibleLists(matching: "zzz").isEmpty)
        #expect(store.visibleLists(matching: "   ").count == 2)
    }
}
