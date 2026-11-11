import Foundation
import Testing
@testable import Bookplate

struct StatsChartsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func book(_ id: String, authors: [String] = ["A"], pages: Int? = nil) -> Book {
        Book(id: id, title: "T\(id)", authors: authors, pageCount: pages, coverUrl: nil, isbn13: nil)
    }

    private func meta(_ id: String, read: Date? = nil, rating: Int? = nil, tags: [String] = []) -> BookMeta {
        BookMeta(bookId: id, status: read == nil ? BookMeta.Status.want : BookMeta.Status.read, rating: rating,
                 notes: nil, notePhotos: [], tags: tags, customCover: nil, addedDate: date(2026, 1),
                 startedDate: nil, finishedDate: read)
    }

    private func insights(_ books: [Book], _ metas: [BookMeta]) -> LibraryInsights {
        LibraryInsights(books: books, metas: metas, now: date(2026, 11), calendar: calendar)
    }

    @Test func monthlyCountsThisYearOnly() {
        let books = (1...5).map { book("\($0)") }
        let result = insights(books, [
            meta("1", read: date(2026, 1)), meta("2", read: date(2026, 1, 31)), meta("3", read: date(2026, 12)),
            meta("4", read: date(2025, 3)), meta("5"),
        ])
        #expect(result.year == 2026)
        #expect(result.finishedPerMonth.count == 12)
        #expect(result.finishedPerMonth.map(\.count) == [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
    }

    @Test func recentReadsNewestFirstCappedAt15() {
        let books = (1...20).map { book("\($0)") }
        let metas = (1...20).map { meta("\($0)", read: date(2026, 1, $0), rating: $0 % 5 + 1) }
        let reads = insights(books, metas).recentReads
        #expect(reads.count == 15)
        #expect(reads.first?.book.id == "20")
        #expect(reads.first?.finished == date(2026, 1, 20))
        #expect(reads.first?.rating == 1)
        #expect(reads.last?.book.id == "6")
    }

    @Test func recentReadsIncludeOtherYearsAndSkipUnfinished() {
        let books = [book("1"), book("2"), book("3")]
        let reads = insights(books, [meta("1", read: date(2024, 5)), meta("2"), meta("gone", read: date(2026, 1))]).recentReads
        #expect(reads.map(\.book.id) == ["1"])
    }

    @Test func ratingDistributionCoversOneToFive() {
        let books = (1...4).map { book("\($0)") }
        let result = insights(books, [meta("1", rating: 5), meta("2", rating: 5), meta("3", rating: 2), meta("4")])
        #expect(result.ratingDistribution.map(\.stars) == [1, 2, 3, 4, 5])
        #expect(result.ratingDistribution.map(\.count) == [0, 1, 0, 0, 2])
    }

    @Test func topAuthorsRankedTiesAlphabeticalCappedAt8() {
        var books = [book("a1", authors: ["Zed"]), book("a2", authors: ["zed", "Amy"]), book("a3", authors: ["Bo"])]
        books += (1...8).map { book("x\($0)", authors: ["Author \($0)"]) }
        let authors = insights(books, []).topAuthors
        #expect(authors.count == 8)
        #expect(authors[0].name == "Zed")
        #expect(authors[0].count == 2)
        #expect(authors.dropFirst().prefix(3).map(\.name) == ["Amy", "Author 1", "Author 2"])
    }

    @Test func topTagsWithPercentages() {
        let books = (1...4).map { book("\($0)") }
        let tags = insights(books, [
            meta("1", tags: ["sci-fi", "Classic"]), meta("2", tags: ["Sci-Fi"]), meta("3", tags: ["classic", "classic"]),
            meta("4"),
        ]).topTags
        #expect(tags.map(\.name) == ["Classic", "sci-fi"])
        #expect(tags.map(\.count) == [2, 2])
        #expect(tags[0].fraction == 0.5)
    }

    @Test func topTagsCappedAt10() {
        let books = [book("1")]
        let tags = insights(books, [meta("1", tags: (1...12).map { "t\($0)" })]).topTags
        #expect(tags.count == 10)
        #expect(tags[0].fraction == 1)
    }

    @Test func pageTotals() throws {
        let books = [book("1", pages: 100), book("2", pages: 301), book("3"), book("4", pages: 0)]
        let pages = try #require(insights(books, []).pages)
        #expect(pages.books == 2)
        #expect(pages.total == 401)
        #expect(pages.average == 201)
        #expect(pages.longest.id == "2")
        #expect(pages.shortest.id == "1")
    }

    @Test func noPageCounts() {
        #expect(insights([book("1")], []).pages == nil)
    }

    @Test func emptyLibrary() {
        let result = insights([], [])
        #expect(result.finishedPerMonth.allSatisfy { $0.count == 0 })
        #expect(result.recentReads.isEmpty)
        #expect(result.topAuthors.isEmpty)
        #expect(result.topTags.isEmpty)
        #expect(result.pages == nil)
    }
}
