import Foundation
import Testing
@testable import Bookplate

struct BookplateBannerTests {
    private func user(_ name: String?) -> AuthUser {
        AuthUser(id: UUID(), email: "reader@example.com", name: name)
    }

    @Test func usesTheAccountName() {
        #expect(BookplateBanner.ownerName(user("Sam Reader")) == "Sam Reader")
        #expect(BookplateBanner.ownerName(user("  Sam  ")) == "Sam")
    }

    @Test func noBannerWithoutAName() {
        #expect(BookplateBanner.ownerName(nil) == nil)
        #expect(BookplateBanner.ownerName(user(nil)) == nil)
        #expect(BookplateBanner.ownerName(user("   ")) == nil)
    }

    @Test func sampleDataHasNoHardCodedOwner() throws {
        let shelves = try Bookshelf.sampleFromBundle()
        #expect(shelves.allSatisfy { !$0.name.localizedCaseInsensitiveContains("abigail") })
        #expect(!Bookshelf.mock.name.localizedCaseInsensitiveContains("abigail"))
    }
}
