import Foundation

/// Totals for the Stats tab, worked out from the books in the library.
struct LibraryStats: Equatable {
    var totalBooks = 0
    /// Distinct authors, ignoring case and accents.
    var totalAuthors = 0
    var totalShelves = 0
    var readCount = 0
    var readingCount = 0
    var ratedCount = 0
    /// Mean of the rated books' stars, nil when nothing is rated.
    var averageRating: Double?

    init(books: [Book], metas: [BookMeta], shelfCount: Int) {
        let bookIds = Set(books.map(\.id))
        let metas = metas.filter { bookIds.contains($0.bookId) }
        totalBooks = books.count
        totalAuthors = Set(books.flatMap(\.authors).map(Self.authorKey).filter { !$0.isEmpty }).count
        totalShelves = shelfCount
        readCount = metas.count { $0.status == BookMeta.Status.read }
        readingCount = metas.count { $0.status == BookMeta.Status.reading }
        let ratings = metas.compactMap(\.rating)
        ratedCount = ratings.count
        averageRating = ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    private static func authorKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

/// Progress toward the reading goal for the year containing `now`.
struct ReadingGoalProgress: Equatable {
    let year: Int
    let goal: Int
    /// Read books whose finish date falls in `year`.
    let finished: Int

    /// Books still to read, never below zero.
    var remaining: Int { max(goal - finished, 0) }
    /// 0...1 for the progress ring.
    var fraction: Double { goal > 0 ? min(Double(finished) / Double(goal), 1) : 0 }
    var isComplete: Bool { finished >= goal }
    /// Months left in the year, counting the current one.
    let monthsLeft: Int
    /// Books to read each month (current month included) to reach the goal.
    var perMonth: Double { remaining == 0 ? 0 : Double(remaining) / Double(max(monthsLeft, 1)) }

    init(goal: Int, metas: [BookMeta], bookIds: Set<String>, now: Date = Date(), calendar: Calendar = .current) {
        let year = calendar.component(.year, from: now)
        self.year = year
        self.goal = goal
        self.monthsLeft = 12 - calendar.component(.month, from: now) + 1
        self.finished = metas.count { meta in
            guard bookIds.contains(meta.bookId), meta.status == BookMeta.Status.read,
                  let date = meta.finishedDate else { return false }
            return calendar.component(.year, from: date) == year
        }
    }
}

extension LibraryStore {
    var stats: LibraryStats {
        LibraryStats(books: books, metas: metas, shelfCount: bookshelf.shelves.count)
    }

    func readingGoalProgress(now: Date = Date(), calendar: Calendar = .current) -> ReadingGoalProgress {
        ReadingGoalProgress(goal: settings.readingGoal, metas: metas, bookIds: Set(books.map(\.id)),
                            now: now, calendar: calendar)
    }
}
