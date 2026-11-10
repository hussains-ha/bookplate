import CoreGraphics
import Foundation
import Testing
@testable import Bookplate

@MainActor
struct ShelfDragTests {
    private let book = Book(id: "x", title: "X", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil)

    /// Three shelves 100pt tall, 14pt apart; spines 30pt wide at centers 15, 47, 79 from x = 12.
    private func drag(lockedC: Bool = false) -> ShelfDrag {
        let drag = ShelfDrag()
        drag.viewport = CGRect(x: 0, y: 0, width: 400, height: 400)
        drag.shelves = [
            "a": .init(frame: CGRect(x: 0, y: 0, width: 400, height: 100), rowOriginX: 12, centers: [15, 47, 79], isLocked: false),
            "b": .init(frame: CGRect(x: 0, y: 114, width: 400, height: 100), rowOriginX: 12, centers: [], isLocked: false),
            "c": .init(frame: CGRect(x: 0, y: 228, width: 400, height: 100), rowOriginX: 12, centers: [15], isLocked: lockedC),
        ]
        drag.picked = .init(book: book, sourceShelfId: "a", spineStart: CGPoint(x: 27, y: 100), fingerStart: CGPoint(x: 27, y: 80))
        return drag
    }

    @Test func nothingIsHoveredWithoutAPickedBook() {
        let drag = drag()
        drag.picked = nil
        drag.finger = CGPoint(x: 50, y: 150)
        #expect(drag.hoveredShelfId == nil && drag.target == nil)
    }

    @Test func overTheSourceShelfThereIsNoTarget() {
        let drag = drag()
        drag.finger = CGPoint(x: 60, y: 50)
        #expect(drag.hoveredShelfId == "a")
        #expect(drag.target == nil)
    }

    @Test func emptyShelfTakesTheBookAtTheStart() {
        let drag = drag()
        drag.finger = CGPoint(x: 200, y: 150)
        #expect(drag.target == .init(shelfId: "b", index: 0))
    }

    @Test func indexFollowsTheSpineCenterAndScrolling() {
        let drag = drag()
        drag.finger = CGPoint(x: 27, y: 260)                 // spine center x = 27 → before c's only spine (12+15)
        #expect(drag.target == .init(shelfId: "c", index: 0))
        drag.finger = CGPoint(x: 40, y: 260)                 // center 40 → after it
        #expect(drag.target == .init(shelfId: "c", index: 1))
        drag.shelves["c"]?.rowOriginX = 40                   // c scrolled: its spine is now at 55
        #expect(drag.target == .init(shelfId: "c", index: 0))
    }

    @Test func gapBetweenShelvesCountsAsTheNearerShelf() {
        let drag = drag()
        drag.finger = CGPoint(x: 50, y: 105)
        #expect(drag.hoveredShelfId == "a")
        drag.finger = CGPoint(x: 50, y: 110)
        #expect(drag.hoveredShelfId == "b")
    }

    @Test func lockedShelvesAndOutsideTheBookcaseAreNotTargets() {
        let drag = drag(lockedC: true)
        drag.finger = CGPoint(x: 50, y: 260)
        #expect(drag.hoveredShelfId == "c")
        #expect(drag.target == nil)
        drag.finger = CGPoint(x: 50, y: 500)
        #expect(drag.hoveredShelfId == nil && drag.target == nil)
    }
}
