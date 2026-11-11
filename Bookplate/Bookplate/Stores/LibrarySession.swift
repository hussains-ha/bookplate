import Foundation
import Observation

/// The signed-in user's libraries and which one is open. Remembers the last opened library.
@MainActor
@Observable
final class LibrarySession {
    let userId: UUID
    /// The account's display name, saved on new libraries for the bookplate shared libraries show.
    let ownerName: String?
    private let directory: LibraryDirectory
    private let defaults: UserDefaults

    private(set) var libraries: [LibraryInfo] = []
    private(set) var currentId: UUID?

    init(userId: UUID, ownerName: String?, directory: LibraryDirectory, defaults: UserDefaults = .standard) {
        self.userId = userId
        self.ownerName = ownerName
        self.directory = directory
        self.defaults = defaults
    }

    var current: LibraryInfo? { libraries.first { $0.id == currentId } }
    var owned: [LibraryInfo] { libraries.filter(\.isOwned) }
    var shared: [LibraryInfo] { libraries.filter { !$0.isOwned } }

    private var selectionKey: String { "selectedLibrary.\(userId.uuidString.lowercased())" }

    /// Loads the libraries and picks the last opened one (or the first). A new account gets "My Library".
    func start() async throws(BookServiceError) {
        libraries = try await directory.libraries()
        if owned.isEmpty {
            let library = try await directory.create(name: "My Library", position: 0, ownerName: ownerName)
            libraries = LibraryInfo.sorted(libraries + [library])
        }
        let saved = defaults.string(forKey: selectionKey).flatMap(UUID.init(uuidString:))
        select(libraries.first { $0.id == saved }?.id ?? owned.first?.id ?? libraries.first?.id)
    }

    /// Reloads the list (e.g. after a friend shares a library). Keeps the open library if it's still there.
    func refresh() async throws(BookServiceError) {
        libraries = try await directory.libraries()
        if current == nil { select(owned.first?.id ?? libraries.first?.id) }
    }

    func select(_ id: UUID?) {
        currentId = id
        if let id { defaults.set(id.uuidString, forKey: selectionKey) }
    }

    func nameProblem(_ name: String, excluding id: UUID? = nil) -> LibraryInfo.NameProblem? {
        LibraryInfo.nameProblem(name, among: libraries, excluding: id)
    }

    /// Creates a library at the end of yours and opens it.
    func create(named name: String) async throws(BookServiceError) -> LibraryInfo? {
        guard nameProblem(name) == nil else { return nil }
        let position = (owned.map(\.position).max() ?? -1) + 1
        let library = try await directory.create(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                                 position: position, ownerName: ownerName)
        libraries = LibraryInfo.sorted(libraries + [library])
        select(library.id)
        return library
    }

    func rename(_ id: UUID, to name: String) async throws(BookServiceError) {
        guard nameProblem(name, excluding: id) == nil,
              let i = libraries.firstIndex(where: { $0.id == id && $0.isOwned }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await directory.rename(id, to: name)
        libraries[i].name = name
    }

    /// You always keep at least one library of your own.
    func canDelete(_ id: UUID) -> Bool {
        owned.count > 1 && owned.contains { $0.id == id }
    }

    /// Deletes one of your libraries and everything in it. Opens another if it was open.
    func delete(_ id: UUID) async throws(BookServiceError) {
        guard canDelete(id) else { return }
        try await directory.delete(id)
        libraries.removeAll { $0.id == id }
        if currentId == id { select(owned.first?.id) }
    }
}
