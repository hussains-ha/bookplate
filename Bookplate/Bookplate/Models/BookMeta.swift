import Foundation

/// A user's personal details for a book they've added. Objective data lives in `Book`.
struct BookMeta: Codable, Identifiable, Hashable, Sendable {
    var id: String { bookId }

    let bookId: String
    /// Free-form so users can define their own statuses; see `Status` for the defaults.
    var status: String
    /// 1...5 stars, nil when unrated.
    var rating: Int?
    var notes: String?
    var notePhotos: [URL]
    var tags: [String]
    var customCover: URL?
    let addedDate: Date
    var startedDate: Date?
    var finishedDate: Date?
}

extension BookMeta {
    enum Status {
        static let want = "want"
        static let reading = "reading"
        static let read = "read"
        static let defaults = [want, reading, read]
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension BookMeta {
    static let mock = BookMeta(
        bookId: "book-atomic-habits",
        status: Status.read,
        rating: 5,
        notes: "Chapter 4 on habit stacking. Try it with the morning reading block.",
        notePhotos: [],
        tags: ["habits", "self-improvement"],
        customCover: nil,
        addedDate: Date(timeIntervalSince1970: 1_735_689_600),
        startedDate: Date(timeIntervalSince1970: 1_736_294_400),
        finishedDate: Date(timeIntervalSince1970: 1_738_368_000)
    )

    static let mocks: [BookMeta] = [
        .mock,
        BookMeta(bookId: "book-dune", status: Status.reading, rating: nil, notes: nil,
                 notePhotos: [], tags: ["sci-fi"], customCover: nil,
                 addedDate: Date(timeIntervalSince1970: 1_738_454_400),
                 startedDate: Date(timeIntervalSince1970: 1_738_540_800), finishedDate: nil),
        BookMeta(bookId: "book-educated", status: Status.want, rating: nil, notes: nil,
                 notePhotos: [], tags: [], customCover: nil,
                 addedDate: Date(timeIntervalSince1970: 1_738_627_200),
                 startedDate: nil, finishedDate: nil),
    ]

    /// Decodes the bundled `bookmeta.json` sample data.
    static func sampleFromBundle(_ bundle: Bundle = .main) throws -> [BookMeta] {
        guard let url = bundle.url(forResource: "bookmeta", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decoder.decode([BookMeta].self, from: Data(contentsOf: url))
    }
}
