import SwiftUI
import Testing
@testable import Bookplate

struct SpineStatusTests {
    @Test func eachDefaultStatusHasItsOwnDot() {
        #expect(SpineView.statusColor(BookMeta.Status.read) == Theme.statusRead)
        #expect(SpineView.statusColor(BookMeta.Status.reading) == Theme.statusReading)
        #expect(SpineView.statusColor(BookMeta.Status.want) == Theme.statusWant)
    }

    @Test(arguments: [nil, "", "abandoned"] as [String?])
    func noDotWithoutAKnownStatus(_ status: String?) {
        #expect(SpineView.statusColor(status) == nil)
    }
}
