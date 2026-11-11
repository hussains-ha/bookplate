import Foundation
import Supabase

/// Someone with access to a library you own.
struct LibraryMember: Identifiable, Equatable, Codable, Sendable {
    enum Role: String, Codable, CaseIterable, Sendable {
        case view, edit
        var title: String { self == .view ? "Can view" : "Can edit" }
    }

    let userId: UUID
    let email: String
    let name: String?
    var role: Role

    var id: UUID { userId }
    /// Name if they have one, otherwise their email.
    var displayName: String { name ?? email }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email, name, role
    }
}

/// Why an invite didn't go through, worded for the share sheet.
enum ShareProblem: Error, Equatable {
    case invalidEmail
    case noAccount
    case yourself
    case alreadyShared(String)
    case failed(String)

    var message: String {
        switch self {
        case .invalidEmail: "Enter a valid email address."
        case .noAccount: "No Bookplate account uses that email. Ask your friend to sign up first."
        case .yourself: "That's your own email."
        case .alreadyShared(let name): "\(name) already has access. Change their role below."
        case .failed(let message): message
        }
    }

    /// The server's error codes from share_library().
    static func from(_ error: BookServiceError) -> ShareProblem {
        if case .rejected(let message) = error {
            if message.contains("no_account") { return .noAccount }
            if message.contains("self") { return .yourself }
        }
        return .failed(error.localizedDescription)
    }
}

/// Who a library you own is shared with, and changing that.
protocol LibrarySharing {
    func members(of libraryId: UUID) async throws(BookServiceError) -> [LibraryMember]
    /// Gives the account with this email access, or changes their role. Returns everyone with access.
    func share(_ libraryId: UUID, withEmail email: String, role: LibraryMember.Role) async throws(BookServiceError) -> [LibraryMember]
    func remove(_ userId: UUID, from libraryId: UUID) async throws(BookServiceError)
    func stopSharing(_ libraryId: UUID) async throws(BookServiceError)
}

struct SupabaseLibrarySharing: LibrarySharing {
    var client: SupabaseClient = SupabaseService.client

    private struct LibraryParam: Encodable {
        let p_library_id: UUID
    }

    private struct ShareParams: Encodable {
        let p_library_id: UUID
        let p_email: String
        let p_role: String
    }

    func members(of libraryId: UUID) async throws(BookServiceError) -> [LibraryMember] {
        try await run {
            try await client.rpc("library_member_list", params: LibraryParam(p_library_id: libraryId)).execute().value
        }
    }

    func share(_ libraryId: UUID, withEmail email: String, role: LibraryMember.Role) async throws(BookServiceError) -> [LibraryMember] {
        try await run {
            try await client.rpc("share_library", params: ShareParams(p_library_id: libraryId, p_email: email,
                                                                       p_role: role.rawValue)).execute().value
        }
    }

    func remove(_ userId: UUID, from libraryId: UUID) async throws(BookServiceError) {
        try await run {
            try await client.from("library_members").delete()
                .eq("library_id", value: libraryId).eq("user_id", value: userId).execute()
        }
    }

    func stopSharing(_ libraryId: UUID) async throws(BookServiceError) {
        try await run {
            try await client.from("library_members").delete().eq("library_id", value: libraryId).execute()
        }
    }

    private func run<T>(_ request: () async throws -> T) async throws(BookServiceError) -> T {
        try await BookService.requireSession(client)
        do {
            return try await request()
        } catch {
            throw BookService.failure(from: error)
        }
    }
}

/// For tests and previews: accounts are looked up in `accounts` by email.
final class InMemoryLibrarySharing: LibrarySharing {
    var accounts: [String: (id: UUID, name: String?)]
    let ownerEmail: String
    private(set) var membersByLibrary: [UUID: [LibraryMember]] = [:]

    init(ownerEmail: String = "me@example.com", accounts: [String: (id: UUID, name: String?)] = [:]) {
        self.ownerEmail = ownerEmail
        self.accounts = accounts
    }

    func members(of libraryId: UUID) async throws(BookServiceError) -> [LibraryMember] {
        membersByLibrary[libraryId] ?? []
    }

    func share(_ libraryId: UUID, withEmail email: String, role: LibraryMember.Role) async throws(BookServiceError) -> [LibraryMember] {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        if email == ownerEmail.lowercased() { throw .rejected("self") }
        guard let account = accounts[email] else { throw .rejected("no_account") }
        var members = membersByLibrary[libraryId] ?? []
        if let i = members.firstIndex(where: { $0.userId == account.id }) {
            members[i].role = role
        } else {
            members.append(LibraryMember(userId: account.id, email: email, name: account.name, role: role))
        }
        membersByLibrary[libraryId] = members
        return members
    }

    func remove(_ userId: UUID, from libraryId: UUID) async throws(BookServiceError) {
        membersByLibrary[libraryId]?.removeAll { $0.userId == userId }
    }

    func stopSharing(_ libraryId: UUID) async throws(BookServiceError) {
        membersByLibrary[libraryId] = []
    }
}

/// The share sheet's state for one library you own.
@MainActor
@Observable
final class ShareModel {
    let libraryId: UUID
    private let sharing: LibrarySharing
    private(set) var members: [LibraryMember] = []
    private(set) var isWorking = false

    init(libraryId: UUID, sharing: LibrarySharing) {
        self.libraryId = libraryId
        self.sharing = sharing
    }

    func load() async throws(BookServiceError) {
        members = try await sharing.members(of: libraryId)
    }

    /// Invites by email. Checks the address and existing access first, so the server is only asked when it can work.
    func invite(email: String, role: LibraryMember.Role) async throws(ShareProblem) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else { throw .invalidEmail }
        if let member = members.first(where: { $0.email.caseInsensitiveCompare(email) == .orderedSame }) {
            throw .alreadyShared(member.displayName)
        }
        isWorking = true
        defer { isWorking = false }
        do {
            members = try await sharing.share(libraryId, withEmail: email, role: role)
        } catch {
            throw ShareProblem.from(error)
        }
    }

    func setRole(_ role: LibraryMember.Role, for member: LibraryMember) async throws(BookServiceError) {
        guard member.role != role else { return }
        members = try await sharing.share(libraryId, withEmail: member.email, role: role)
    }

    func remove(_ member: LibraryMember) async throws(BookServiceError) {
        try await sharing.remove(member.userId, from: libraryId)
        members.removeAll { $0.userId == member.userId }
    }

    func stopSharing() async throws(BookServiceError) {
        try await sharing.stopSharing(libraryId)
        members = []
    }

    static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !email.contains(" ")
    }
}
