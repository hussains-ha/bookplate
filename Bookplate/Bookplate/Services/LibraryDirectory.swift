import Foundation
import Supabase

/// The libraries the signed-in user can open, and creating, renaming and deleting their own.
protocol LibraryDirectory {
    func libraries() async throws(BookServiceError) -> [LibraryInfo]
    func create(name: String, position: Int, ownerName: String?) async throws(BookServiceError) -> LibraryInfo
    func rename(_ id: UUID, to name: String) async throws(BookServiceError)
    /// Also deletes everything in it (books, shelves, lists).
    func delete(_ id: UUID) async throws(BookServiceError)
    /// Gives up your access to a library shared with you.
    func leave(_ id: UUID) async throws(BookServiceError)
}

/// A `libraries` row.
struct LibraryRow: Codable, Equatable {
    var id: UUID
    var name: String
    var ownerId: UUID
    var ownerName: String?
    var position: Int

    enum CodingKeys: String, CodingKey {
        case id, name, position
        case ownerId = "owner_id"
        case ownerName = "owner_name"
    }

    func info(for userId: UUID, access shared: LibraryInfo.Access = .view) -> LibraryInfo {
        LibraryInfo(id: id, name: name, ownerId: ownerId, ownerName: ownerName, position: position,
                    access: ownerId == userId ? .owner : shared)
    }
}

/// A `library_members` row as seen by the member.
struct MembershipRoleRow: Decodable {
    let libraryId: UUID
    let role: String

    enum CodingKeys: String, CodingKey {
        case libraryId = "library_id"
        case role
    }
}

struct SupabaseLibraryDirectory: LibraryDirectory {
    let userId: UUID
    var client: SupabaseClient = SupabaseService.client

    func libraries() async throws(BookServiceError) -> [LibraryInfo] {
        try await run {
            async let rows: [LibraryRow] = client.from("libraries")
                .select("id,name,owner_id,owner_name,position").execute().value
            // Your role in libraries shared with you.
            async let memberships: [MembershipRoleRow] = client.from("library_members")
                .select("library_id,role").eq("user_id", value: userId).execute().value
            let roles = Dictionary(try await memberships.map { ($0.libraryId, $0.role) }, uniquingKeysWith: { a, _ in a })
            return LibraryInfo.sorted(try await rows.map { row in
                row.info(for: userId, access: roles[row.id] == "edit" ? .edit : .view)
            })
        }
    }

    func create(name: String, position: Int, ownerName: String?) async throws(BookServiceError) -> LibraryInfo {
        try await run {
            let row = LibraryRow(id: UUID(), name: name, ownerId: userId, ownerName: ownerName, position: position)
            try await client.from("libraries").insert(row, returning: .minimal).execute()
            return row.info(for: userId)
        }
    }

    func rename(_ id: UUID, to name: String) async throws(BookServiceError) {
        try await run {
            try await client.from("libraries").update(["name": name]).eq("id", value: id).execute()
        }
    }

    func delete(_ id: UUID) async throws(BookServiceError) {
        try await run {
            try await client.from("libraries").delete().eq("id", value: id).execute()
        }
    }

    func leave(_ id: UUID) async throws(BookServiceError) {
        try await run {
            try await client.from("library_members").delete().eq("library_id", value: id).eq("user_id", value: userId).execute()
        }
    }

    private func run<T>(_ request: () async throws -> T) async throws(BookServiceError) -> T {
        try await BookService.requireSession(client)
        guard client.auth.currentUser?.id == userId else { throw .notSignedIn }
        do {
            return try await request()
        } catch {
            throw BookService.failure(from: error)
        }
    }
}

/// For tests and previews.
final class InMemoryLibraryDirectory: LibraryDirectory {
    private(set) var items: [LibraryInfo]
    let userId: UUID
    var error: BookServiceError?

    init(userId: UUID = UUID(), libraries: [LibraryInfo] = []) {
        self.userId = userId
        self.items = libraries
    }

    func libraries() async throws(BookServiceError) -> [LibraryInfo] {
        if let error { throw error }
        return LibraryInfo.sorted(items)
    }

    func create(name: String, position: Int, ownerName: String?) async throws(BookServiceError) -> LibraryInfo {
        if let error { throw error }
        let info = LibraryInfo(id: UUID(), name: name, ownerId: userId, ownerName: ownerName, position: position, access: .owner)
        items.append(info)
        return info
    }

    func rename(_ id: UUID, to name: String) async throws(BookServiceError) {
        if let error { throw error }
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].name = name }
    }

    func delete(_ id: UUID) async throws(BookServiceError) {
        if let error { throw error }
        items.removeAll { $0.id == id }
    }

    func leave(_ id: UUID) async throws(BookServiceError) {
        if let error { throw error }
        items.removeAll { $0.id == id && $0.ownerId != userId }
    }
}
