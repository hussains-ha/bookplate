import Foundation
import Testing
@testable import Bookplate

@MainActor
struct KindleLinkTests {
    @Test func opensTheKindleScheme() {
        #expect(KindleLink.url.absoluteString == "kindle://")
        #expect(KindleLink.url.scheme == "kindle")
    }

    @Test func installedFollowsCanOpen() {
        var asked: URL?
        #expect(KindleLink.isInstalled { asked = $0; return true })
        #expect(asked == KindleLink.url)
        #expect(!KindleLink.isInstalled { _ in false })
    }

    @Test func infoPlistDeclaresTheKindleQueryScheme() throws {
        let schemes = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String]
        #expect(schemes?.contains("kindle") == true)
    }
}
