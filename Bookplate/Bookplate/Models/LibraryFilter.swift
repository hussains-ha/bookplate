import Foundation

/// Which books the library shows, chosen from the filter menu next to search.
enum LibraryFilter: Hashable, Sendable {
    case all
    /// One of `BookMeta.Status`.
    case status(String)
    /// Rated 5 stars.
    case favorites
    /// Has this tag (compared ignoring case).
    case tag(String)

    /// The menu's statuses, in menu order.
    static let statuses = [BookMeta.Status.reading, BookMeta.Status.want, BookMeta.Status.read]

    var title: String {
        switch self {
        case .all: "All books"
        case .status(let status): Self.statusTitle(status)
        case .favorites: "Favorites"
        case .tag(let tag): "#\(tag)"
        }
    }

    static func statusTitle(_ status: String) -> String {
        switch status {
        case BookMeta.Status.reading: "Currently reading"
        case BookMeta.Status.want: "Want to read"
        case BookMeta.Status.read: "Read"
        default: status.capitalized
        }
    }

    func matches(_ meta: BookMeta?) -> Bool {
        switch self {
        case .all: true
        case .status(let status): meta?.status == status
        case .favorites: meta?.rating == 5
        case .tag(let tag): meta?.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } ?? false
        }
    }
}
