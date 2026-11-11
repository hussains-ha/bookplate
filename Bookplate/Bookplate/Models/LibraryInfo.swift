import Foundation

/// One library the signed-in user can open: their own, or one shared with them.
struct LibraryInfo: Identifiable, Equatable, Hashable, Sendable {
    enum Access: String, Codable, Sendable {
        case owner
        /// Shared with you: can look, not change.
        case view
        /// Shared with you: can change it.
        case edit
    }

    let id: UUID
    var name: String
    let ownerId: UUID
    /// The owner's display name, for the bookplate and "Shared by …".
    var ownerName: String?
    var position: Int
    var access: Access

    var isOwned: Bool { access == .owner }
    var canEdit: Bool { access != .view }

    static let maxNameLength = 40

    enum NameProblem: Equatable {
        case blank, tooLong, duplicate

        var message: String {
            switch self {
            case .blank: "Enter a name for the library."
            case .tooLong: "Library names can be up to \(LibraryInfo.maxNameLength) characters."
            case .duplicate: "You already have a library with that name."
            }
        }
    }

    /// Why `name` can't be used for one of your libraries, or nil. Compared trimmed and ignoring case
    /// against your own libraries only; pass the one being renamed as `excluding`.
    static func nameProblem(_ name: String, among libraries: [LibraryInfo], excluding id: UUID? = nil) -> NameProblem? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .blank }
        if name.count > maxNameLength { return .tooLong }
        let taken = libraries.contains {
            $0.isOwned && $0.id != id
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
        }
        return taken ? .duplicate : nil
    }

    /// Your libraries first (in your order), then shared ones by owner and name.
    static func sorted(_ libraries: [LibraryInfo]) -> [LibraryInfo] {
        libraries.sorted { a, b in
            if a.isOwned != b.isOwned { return a.isOwned }
            if a.isOwned { return (a.position, a.name) < (b.position, b.name) }
            return ((a.ownerName ?? ""), a.name) < ((b.ownerName ?? ""), b.name)
        }
    }
}
