import Foundation

/// How one shelf's books are shown. Display only: the saved shelf order never changes.
enum ShelfSort: String, CaseIterable, Identifiable, Sendable {
    /// The saved order (the default).
    case custom
    case title
    case author
    case rating

    var id: Self { self }

    var title: String {
        switch self {
        case .custom: "Custom"
        case .title: "Title A→Z"
        case .author: "Author A→Z"
        case .rating: "Rating"
        }
    }

    /// The books in this order. Ties keep their saved order.
    /// - Author: by the first author's last name, then first name, then title.
    /// - Rating: highest first, unrated last.
    func apply(to books: [Book], rating: (Book) -> Int?) -> [Book] {
        let indexed = Array(books.enumerated())
        let sorted: [(offset: Int, element: Book)]
        switch self {
        case .custom:
            return books
        case .title:
            sorted = indexed.sorted { Self.ordered($0.element.title, $1.element.title, else: $0.offset < $1.offset) }
        case .author:
            let keys = indexed.map { Self.authorKey($0.element) }
            sorted = indexed.sorted { a, b in
                let byTitle = { Self.ordered(a.element.title, b.element.title, else: a.offset < b.offset) }
                switch (keys[a.offset], keys[b.offset]) {
                case let (ka?, kb?): return Self.ordered(ka, kb, else: byTitle())
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return byTitle()
                }
            }
        case .rating:
            let ratings = indexed.map { rating($0.element) }
            sorted = indexed.sorted { a, b in
                switch (ratings[a.offset], ratings[b.offset]) {
                case let (ra?, rb?) where ra != rb: ra > rb
                case (_?, nil): true
                case (nil, _?): false
                default: a.offset < b.offset
                }
            }
        }
        return sorted.map { $0.element }
    }

    /// "Frank Herbert" → "Herbert Frank"; nil without an author (those sort last).
    static func authorKey(_ book: Book) -> String? {
        guard let author = book.authors.first?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty
        else { return nil }
        var words = author.split(separator: " ").map(String.init)
        let last = words.removeLast()
        return ([last] + words).joined(separator: " ")
    }

    /// Natural, case- and accent-insensitive order; `tie` decides equal strings.
    private static func ordered(_ a: String, _ b: String, else tie: @autoclosure () -> Bool) -> Bool {
        switch a.localizedStandardCompare(b) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: tie()
        }
    }
}
