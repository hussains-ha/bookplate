import Foundation
import Testing
@testable import Bookplate

struct BundleIdentifierTests {
    @Test func appHasItsRealBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "com.bookplate.app")
    }
}
