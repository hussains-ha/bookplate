import Testing
@testable import Bookplate

struct BookTests {
    @Test func spineWidthDefaultsWithoutPageCount() {
        #expect(SpineView.width(forPageCount: nil) == SpineView.defaultWidth)
        #expect(SpineView.width(forPageCount: 0) == SpineView.defaultWidth)
    }

    @Test func spineWidthIsClamped() {
        #expect(SpineView.width(forPageCount: 10) == SpineView.minWidth)
        #expect(SpineView.width(forPageCount: 5000) == SpineView.maxWidth)
    }

    @Test func sampleBooksDecode() throws {
        #expect(try !Book.sampleFromBundle().isEmpty)
    }
}
