import Foundation
import Testing
@testable import Bookplate

@MainActor
struct ShareLibraryTests {
    private let maya = UUID()
    private let library = UUID()

    private func model() -> (ShareModel, InMemoryLibrarySharing) {
        let sharing = InMemoryLibrarySharing(ownerEmail: "me@example.com",
                                             accounts: ["maya@example.com": (maya, "Maya"), "sam@example.com": (UUID(), nil)])
        return (ShareModel(libraryId: library, sharing: sharing), sharing)
    }

    @Test func invitesByEmailWithARole() async throws {
        let (model, sharing) = model()
        try await model.invite(email: " Maya@Example.com ", role: .edit)
        #expect(model.members.map(\.displayName) == ["Maya"])
        #expect(model.members.first?.role == .edit)
        #expect(sharing.membersByLibrary[library]?.count == 1)
    }

    @Test func memberWithoutANameShowsTheirEmail() async throws {
        let (model, _) = model()
        try await model.invite(email: "sam@example.com", role: .view)
        #expect(model.members.first?.displayName == "sam@example.com")
    }

    @Test func rejectsBadEmailUnknownAccountYourselfAndDuplicates() async throws {
        let (model, _) = model()
        await #expect(throws: ShareProblem.invalidEmail) { try await model.invite(email: "maya", role: .view) }
        await #expect(throws: ShareProblem.noAccount) { try await model.invite(email: "nobody@example.com", role: .view) }
        await #expect(throws: ShareProblem.yourself) { try await model.invite(email: "me@example.com", role: .view) }
        try await model.invite(email: "maya@example.com", role: .view)
        await #expect(throws: ShareProblem.alreadyShared("Maya")) { try await model.invite(email: "MAYA@example.com", role: .edit) }
    }

    @Test func changeRoleRemoveAndStopSharing() async throws {
        let (model, sharing) = model()
        try await model.invite(email: "maya@example.com", role: .view)
        try await model.invite(email: "sam@example.com", role: .view)
        try await model.setRole(.edit, for: model.members[0])
        #expect(model.members[0].role == .edit)
        try await model.remove(model.members[1])
        #expect(model.members.map(\.displayName) == ["Maya"])
        try await model.stopSharing()
        #expect(model.members.isEmpty)
        #expect(sharing.membersByLibrary[library]?.isEmpty == true)
    }

    @Test func loadsExistingMembers() async throws {
        let (first, sharing) = model()
        try await first.invite(email: "maya@example.com", role: .view)
        let second = ShareModel(libraryId: library, sharing: sharing)
        try await second.load()
        #expect(second.members.map(\.userId) == [maya])
    }

    @Test func serverErrorsBecomeFriendlyProblems() {
        #expect(ShareProblem.from(.rejected("no_account")) == .noAccount)
        #expect(ShareProblem.from(.rejected("self")) == .yourself)
        #expect(ShareProblem.from(.network) == .failed(BookServiceError.network.localizedDescription))
        #expect(ShareProblem.noAccount.message.contains("sign up"))
        // Whole codes only: "itself" isn't "self".
        #expect(ShareProblem.from(.rejected("row refers to itself")) == .failed(BookServiceError.rejected("row refers to itself").localizedDescription))
        #expect(ShareProblem.from(.rejected("not_owner")) != .failed("not_owner"))
    }

    @Test func memberRowDecodes() throws {
        let json = #"[{"user_id":"\#(maya.uuidString)","email":"maya@example.com","name":null,"role":"edit"}]"#
        let members = try JSONDecoder().decode([LibraryMember].self, from: Data(json.utf8))
        #expect(members == [LibraryMember(userId: maya, email: "maya@example.com", name: nil, role: .edit)])
    }

    @Test func membershipRoleRowDecodes() throws {
        let json = #"[{"library_id":"\#(library.uuidString)","role":"view"}]"#
        let rows = try JSONDecoder().decode([MembershipRoleRow].self, from: Data(json.utf8))
        #expect(rows.first?.libraryId == library)
        #expect(rows.first?.role == "view")
    }
}
