import Foundation

/// Chart data for the Stats tab, worked out from the books in the library.
struct LibraryInsights: Equatable {
    struct MonthCount: Equatable, Identifiable {
        /// 1...12
        let month: Int
        let count: Int
        var id: Int { month }
    }

    struct RecentRead: Equatable, Identifiable {
        let book: Book
        let finished: Date
        let rating: Int?
        var id: String { book.id }
    }

    struct RatingCount: Equatable, Identifiable {
        /// 1...5
        let stars: Int
        let count: Int
        var id: Int { stars }
    }

    struct NameCount: Equatable, Identifiable {
        let name: String
        let count: Int
        /// Share of the library's books, 0...1.
        let fraction: Double
        var id: String { name }
    }

    struct PageTotals: Equatable {
        let books: Int
        let total: Int
        let average: Int
        let longest: Book
        let shortest: Book
    }

    static let recentLimit = 15
    static let authorLimit = 8
    static let tagLimit = 10

    let year: Int
    /// All twelve months of `year`, in order.
    let finishedPerMonth: [MonthCount]
    /// Read books with a finish date, newest first.
    let recentReads: [RecentRead]
    /// 1 to 5 stars, in order, zero counts included.
    let ratingDistribution: [RatingCount]
    let topAuthors: [NameCount]
    let topTags: [NameCount]
    /// From books that have a page count; nil when none do.
    let pages: PageTotals?

    init(books: [Book], metas: [BookMeta], now: Date = Date(), calendar: Calendar = .current) {
        let byId = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let metas = metas.filter { byId[$0.bookId] != nil }
        let year = calendar.component(.year, from: now)
        self.year = year

        let finished = metas.compactMap { meta -> (BookMeta, Date)? in
            guard meta.status == BookMeta.Status.read, let date = meta.finishedDate else { return nil }
            return (meta, date)
        }
        var months = Array(repeating: 0, count: 12)
        for (_, date) in finished where calendar.component(.year, from: date) == year {
            months[calendar.component(.month, from: date) - 1] += 1
        }
        finishedPerMonth = months.enumerated().map { MonthCount(month: $0.offset + 1, count: $0.element) }

        recentReads = finished
            .sorted { ($0.1, $0.0.bookId) > ($1.1, $1.0.bookId) }
            .prefix(Self.recentLimit)
            .compactMap { meta, date in byId[meta.bookId].map { RecentRead(book: $0, finished: date, rating: meta.rating) } }

        let ratings = metas.compactMap(\.rating)
        ratingDistribution = (1...5).map { stars in RatingCount(stars: stars, count: ratings.count { $0 == stars }) }

        let total = books.count
        topAuthors = Self.top(books.map { Array(Set($0.authors.map(Self.clean).filter { !$0.isEmpty })) },
                              limit: Self.authorLimit, of: total)
        topTags = Self.top(metas.map(\.tags), limit: Self.tagLimit, of: total)

        let paged = books.filter { ($0.pageCount ?? 0) > 0 }
        if let longest = paged.max(by: { ($0.pageCount!, $1.title) < ($1.pageCount!, $0.title) }),
           let shortest = paged.min(by: { ($0.pageCount!, $0.title) < ($1.pageCount!, $1.title) }) {
            let sum = paged.reduce(0) { $0 + $1.pageCount! }
            pages = PageTotals(books: paged.count, total: sum,
                               average: Int((Double(sum) / Double(paged.count)).rounded()),
                               longest: longest, shortest: shortest)
        } else {
            pages = nil
        }
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Names ranked by how many books carry them (most first, ties alphabetical). Names are matched
    /// ignoring case and accents; the first spelling seen is shown. Each book counts once per name.
    private static func top(_ namesPerBook: [[String]], limit: Int, of total: Int) -> [NameCount] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for names in namesPerBook {
            var seen = Set<String>()
            for name in names.map(clean) where !name.isEmpty {
                let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                guard seen.insert(key).inserted else { continue }
                counts[key, default: 0] += 1
                if spelling[key] == nil { spelling[key] = name }
            }
        }
        return counts
            .map { NameCount(name: spelling[$0.key]!, count: $0.value,
                             fraction: total > 0 ? Double($0.value) / Double(total) : 0) }
            .sorted { $0.count != $1.count ? $0.count > $1.count
                      : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }
}

extension LibraryStore {
    func insights(now: Date = Date(), calendar: Calendar = .current) -> LibraryInsights {
        LibraryInsights(books: books, metas: metas, now: now, calendar: calendar)
    }
}
