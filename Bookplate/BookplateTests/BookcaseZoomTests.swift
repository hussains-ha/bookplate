import Foundation
import Testing
@testable import Bookplate

struct BookcaseZoomTests {
    @Test func hasSevenStepsFrom50To145StartingAt100() {
        #expect(BookcaseZoom.steps.count == 7)
        #expect(BookcaseZoom.steps.first == 0.5)
        #expect(BookcaseZoom.steps.last == 1.45)
        #expect(BookcaseZoom.standard.percent == 100)
    }

    @Test func zoomsThroughEveryStepAndStopsAtTheEnds() {
        var zoom = BookcaseZoom(index: 0)
        #expect(!zoom.canZoomOut)
        #expect(zoom.zoomedOut() == zoom)
        var percents = [zoom.percent]
        while zoom.canZoomIn {
            zoom = zoom.zoomedIn()
            percents.append(zoom.percent)
        }
        #expect(percents == [50, 65, 80, 100, 115, 130, 145])
        #expect(zoom.zoomedIn() == zoom)
        #expect(zoom.canZoomOut)
    }

    @Test(arguments: [-3, 99])
    func clampsOutOfRangeIndexes(_ index: Int) {
        let zoom = BookcaseZoom(index: index)
        #expect(BookcaseZoom.steps.indices.contains(zoom.index))
    }

    @Test func spineTextStaysReadable() {
        for scale in BookcaseZoom.steps {
            #expect(BookcaseZoom.titleSize(at: scale) >= 6)
            if let author = BookcaseZoom.authorSize(at: scale) { #expect(author >= 5) }
        }
        #expect(BookcaseZoom.authorSize(at: 0.5) == nil)
        #expect(BookcaseZoom.authorSize(at: 1) == 6.5)
        #expect(BookcaseZoom.titleSize(at: 1.45) > BookcaseZoom.titleSize(at: 1))
    }
}
