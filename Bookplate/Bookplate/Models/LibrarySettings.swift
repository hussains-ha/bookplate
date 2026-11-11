import Foundation

/// A user's library-wide settings, saved with their library.
struct LibrarySettings: Codable, Equatable, Sendable {
    static let defaultReadingGoal = 24
    static let readingGoalRange = 1...999

    /// Books to finish this calendar year.
    var readingGoal: Int = defaultReadingGoal
    /// How the bookcase looks.
    var appearance: Bookshelf.Appearance = .classic
    var bookplate = BookplateDesign()
}
