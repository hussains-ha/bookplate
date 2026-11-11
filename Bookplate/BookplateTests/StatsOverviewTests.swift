import Foundation
import Testing
@testable import Bookplate

@MainActor
struct StatsOverviewTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func book(_ id: String, _ authors: [String]) -> Book {
        Book(id: id, title: id, authors: authors, pageCount: nil, coverUrl: nil, isbn13: nil)
    }

    private func meta(_ id: String, _ status: String = BookMeta.Status.want, rating: Int? = nil,
                      started: Date? = nil, finished: Date? = nil) -> BookMeta {
        BookMeta(bookId: id, status: status, rating: rating, notes: nil, notePhotos: [], tags: [],
                 customCover: nil, addedDate: date(2026, 1), startedDate: started, finishedDate: finished)
    }

    private func store(_ books: [Book], _ metas: [BookMeta], shelves: Int = 2,
                       settings: LibrarySettings = LibrarySettings()) -> LibraryStore {
        let shelves = (0..<shelves).map { Shelf(id: "s\($0)", name: "S\($0)", bookIds: []) }
        return LibraryStore(books: books, metas: metas,
                            bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic),
                            settings: settings, coverLookup: NoCoverLookup())
    }

    // MARK: Overview

    @Test func countsTotals() {
        let store = store(
            [book("1", ["Ann Lee"]), book("2", ["ann lee", "Bo Chen"]), book("3", ["Zoë Ray"]), book("4", [])],
            [meta("1", BookMeta.Status.read, rating: 5), meta("2", BookMeta.Status.read, rating: 4),
             meta("3", BookMeta.Status.reading, rating: 2), meta("4")],
            shelves: 3)
        let stats = store.stats
        #expect(stats.totalBooks == 4)
        #expect(stats.totalAuthors == 3)
        #expect(stats.totalShelves == 3)
        #expect(stats.readCount == 2)
        #expect(stats.readingCount == 1)
        #expect(stats.ratedCount == 3)
        #expect(stats.averageRating == 11.0 / 3.0)
    }

    @Test func authorsIgnoreAccents() {
        let store = store([book("1", ["Zoë Ray"]), book("2", ["Zoe Ray"])], [meta("1"), meta("2")])
        #expect(store.stats.totalAuthors == 1)
    }

    @Test func emptyLibrary() {
        let stats = store([], [], shelves: 1).stats
        #expect(stats.totalBooks == 0)
        #expect(stats.totalAuthors == 0)
        #expect(stats.ratedCount == 0)
        #expect(stats.averageRating == nil)
    }

    @Test func ignoresDetailsForBooksNotInTheLibrary() {
        let store = store([book("1", ["A"])], [meta("1"), meta("gone", BookMeta.Status.read, rating: 1)])
        #expect(store.stats.readCount == 0)
        #expect(store.stats.averageRating == nil)
    }

    // MARK: Reading goal

    @Test func goalCountsBooksFinishedThisYear() {
        let books = (1...4).map { book("\($0)", ["A"]) }
        let store = store(books, [
            meta("1", BookMeta.Status.read, finished: date(2026, 2)),
            meta("2", BookMeta.Status.read, finished: date(2025, 12, 31)),
            meta("3", BookMeta.Status.read, finished: nil),
            meta("4", BookMeta.Status.reading, finished: date(2026, 3)),
        ], settings: LibrarySettings(readingGoal: 10))
        let progress = store.readingGoalProgress(now: date(2026, 11), calendar: calendar)
        #expect(progress.year == 2026)
        #expect(progress.goal == 10)
        #expect(progress.finished == 1)
        #expect(progress.remaining == 9)
        #expect(progress.monthsLeft == 2)
        #expect(progress.perMonth == 4.5)
        #expect(progress.fraction == 0.1)
        #expect(!progress.isComplete)
    }

    @Test func goalDefaultsTo24() {
        let progress = store([], []).readingGoalProgress(now: date(2026, 1), calendar: calendar)
        #expect(progress.goal == 24)
        #expect(progress.monthsLeft == 12)
        #expect(progress.perMonth == 2)
    }

    @Test func goalReachedCapsTheRing() {
        let store = store([book("1", ["A"]), book("2", ["B"])], [
            meta("1", BookMeta.Status.read, finished: date(2026, 1)),
            meta("2", BookMeta.Status.read, finished: date(2026, 2)),
        ], settings: LibrarySettings(readingGoal: 1))
        let progress = store.readingGoalProgress(now: date(2026, 12), calendar: calendar)
        #expect(progress.isComplete)
        #expect(progress.remaining == 0)
        #expect(progress.perMonth == 0)
        #expect(progress.fraction == 1)
    }

    @Test func setReadingGoalClampsAndSkipsNoChange() {
        let store = store([], [])
        store.setReadingGoal(0)
        #expect(store.settings.readingGoal == 1)
        store.setReadingGoal(5000)
        #expect(store.settings.readingGoal == 999)
        store.setReadingGoal(30)
        #expect(store.settings.readingGoal == 30)
    }

    @Test func readingGoalIsSavedAndLoaded() async throws {
        let repo = InMemoryLibraryRepository()
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        #expect(store.settings.readingGoal == 24)
        store.setReadingGoal(12)
        store.setReadingGoal(12)
        await sync.waitUntilIdle()
        #expect(repo.applied == [.saveSettings(LibrarySettings(readingGoal: 12))])
        let reloaded = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                           localFiles: nil, coverLookup: NoCoverLookup())
        #expect(reloaded.settings.readingGoal == 12)
    }

    @Test func settingsRowDecodesAndDefaults() throws {
        let rows = try JSONDecoder().decode([SettingsRow].self, from: Data(#"[{"reading_goal":7}]"#.utf8))
        let snapshot = LibrarySnapshot(books: [], metas: [], shelves: [], shelfBooks: [], lists: [], listBooks: [],
                                       settings: rows)
        #expect(snapshot.settings.readingGoal == 7)
        let empty = LibrarySnapshot(books: [], metas: [], shelves: [], shelfBooks: [], lists: [], listBooks: [])
        #expect(empty.settings.readingGoal == 24)
    }

    // MARK: Status dates

    @Test func statusChangesSetAndClearDates() throws {
        let store = store([book("1", ["A"])], [meta("1")])
        let start = date(2026, 3)
        let end = date(2026, 4)
        store.setStatus(BookMeta.Status.reading, for: "1", now: start)
        #expect(store.meta(for: "1")?.startedDate == start)
        #expect(store.meta(for: "1")?.finishedDate == nil)

        store.setStatus(BookMeta.Status.read, for: "1", now: end)
        #expect(store.meta(for: "1")?.startedDate == start)   // kept
        #expect(store.meta(for: "1")?.finishedDate == end)

        store.setStatus(BookMeta.Status.reading, for: "1", now: date(2026, 5))
        #expect(store.meta(for: "1")?.startedDate == start)
        #expect(store.meta(for: "1")?.finishedDate == nil)

        store.setStatus(BookMeta.Status.want, for: "1", now: date(2026, 6))
        #expect(store.meta(for: "1")?.startedDate == nil)
        #expect(store.meta(for: "1")?.finishedDate == nil)
    }

    @Test func markingReadDirectlySetsBothDates() {
        let store = store([book("1", ["A"])], [meta("1")])
        let now = date(2026, 7)
        store.setStatus(BookMeta.Status.read, for: "1", now: now)
        #expect(store.meta(for: "1")?.startedDate == now)
        #expect(store.meta(for: "1")?.finishedDate == now)
        #expect(store.readingGoalProgress(now: now, calendar: calendar).finished == 1)
    }

    @Test func sameStatusKeepsDates() {
        let finished = date(2025, 5)
        let store = store([book("1", ["A"])], [meta("1", BookMeta.Status.read, started: finished, finished: finished)])
        store.setStatus(BookMeta.Status.read, for: "1", now: date(2026, 7))
        #expect(store.meta(for: "1")?.finishedDate == finished)
    }
}
