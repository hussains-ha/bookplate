import CoreGraphics
import Testing
@testable import Bookplate

@MainActor
struct LibraryStoreMoveTests {
    private func store(_ ids: [String]) -> LibraryStore {
        let shelves = [Shelf(id: "s1", name: "One", bookIds: ids), Shelf(id: "s2", name: "Two", bookIds: ["x", "y"])]
        return LibraryStore(books: [], metas: [],
                            bookshelf: Bookshelf(id: "b", name: "B", shelves: shelves, appearance: .classic))
    }

    @Test func movesForward() {
        let store = store(["a", "b", "c", "d"])
        #expect(store.moveBook("a", onShelf: "s1", to: 2))
        #expect(store.bookshelf.shelves[0].bookIds == ["b", "c", "a", "d"])
    }

    @Test func movesBackward() {
        let store = store(["a", "b", "c", "d"])
        #expect(store.moveBook("d", onShelf: "s1", to: 1))
        #expect(store.bookshelf.shelves[0].bookIds == ["a", "d", "b", "c"])
    }

    @Test func droppingInOriginalSpotChangesNothing() {
        let store = store(["a", "b", "c"])
        #expect(!store.moveBook("b", onShelf: "s1", to: 1))
        #expect(store.bookshelf.shelves[0].bookIds == ["a", "b", "c"])
    }

    @Test func clampsOutOfRangeIndex() {
        let store = store(["a", "b", "c"])
        #expect(store.moveBook("a", onShelf: "s1", to: 99))
        #expect(store.bookshelf.shelves[0].bookIds == ["b", "c", "a"])
        #expect(store.moveBook("a", onShelf: "s1", to: -5))
        #expect(store.bookshelf.shelves[0].bookIds == ["a", "b", "c"])
    }

    @Test func unknownShelfOrBookIsRejected() {
        let store = store(["a", "b"])
        #expect(!store.moveBook("a", onShelf: "nope", to: 1))
        #expect(!store.moveBook("zzz", onShelf: "s1", to: 1))
        #expect(store.bookshelf.shelves[0].bookIds == ["a", "b"])
    }

    @Test func otherShelvesAreUntouched() {
        let store = store(["a", "b", "c"])
        store.moveBook("a", onShelf: "s1", to: 2)
        #expect(store.bookshelf.shelves[1].bookIds == ["x", "y"])
    }
}

struct ShelfReorderTests {
    // Spines of width 20, 30, 40 with 2pt gaps: centers at 10, 37, 74.
    private let widths: [CGFloat] = [20, 30, 40]

    @Test func centersFollowWidthsAndSpacing() {
        #expect(ShelfReorder.center(ofIndex: 0, widths: widths, spacing: 2) == 10)
        #expect(ShelfReorder.center(ofIndex: 1, widths: widths, spacing: 2) == 37)
        #expect(ShelfReorder.center(ofIndex: 2, widths: widths, spacing: 2) == 74)
    }

    @Test func draggingRightPastNeighborsRaisesTheTarget() {
        #expect(ShelfReorder.targetIndex(draggedCenter: 10, pickedIndex: 0, widths: widths, spacing: 2) == 0)
        #expect(ShelfReorder.targetIndex(draggedCenter: 40, pickedIndex: 0, widths: widths, spacing: 2) == 1)
        #expect(ShelfReorder.targetIndex(draggedCenter: 200, pickedIndex: 0, widths: widths, spacing: 2) == 2)
    }

    @Test func draggingLeftLowersTheTarget() {
        #expect(ShelfReorder.targetIndex(draggedCenter: 74, pickedIndex: 2, widths: widths, spacing: 2) == 2)
        #expect(ShelfReorder.targetIndex(draggedCenter: 30, pickedIndex: 2, widths: widths, spacing: 2) == 1)
        #expect(ShelfReorder.targetIndex(draggedCenter: -50, pickedIndex: 2, widths: widths, spacing: 2) == 0)
    }

    @Test func slotOffsetMatchesJumpedSpines() {
        #expect(ShelfReorder.slotOffset(pickedIndex: 0, targetIndex: 2, widths: widths, spacing: 2) == 74)
        #expect(ShelfReorder.slotOffset(pickedIndex: 2, targetIndex: 0, widths: widths, spacing: 2) == -54)
        #expect(ShelfReorder.slotOffset(pickedIndex: 1, targetIndex: 1, widths: widths, spacing: 2) == 0)
    }

    @Test func spinesBetweenSlideOneSlotTowardTheOldSpot() {
        // Picking up index 0 (width 20) and targeting 2 slides indices 1 and 2 left by 22.
        #expect(ShelfReorder.shift(forIndex: 1, pickedIndex: 0, targetIndex: 2, widths: widths, spacing: 2) == -22)
        #expect(ShelfReorder.shift(forIndex: 2, pickedIndex: 0, targetIndex: 2, widths: widths, spacing: 2) == -22)
        // Picking up index 2 (width 40) and targeting 0 slides indices 0 and 1 right by 42.
        #expect(ShelfReorder.shift(forIndex: 0, pickedIndex: 2, targetIndex: 0, widths: widths, spacing: 2) == 42)
        #expect(ShelfReorder.shift(forIndex: 1, pickedIndex: 2, targetIndex: 0, widths: widths, spacing: 2) == 42)
    }

    @Test func spinesOutsideTheMoveStayPut() {
        #expect(ShelfReorder.shift(forIndex: 2, pickedIndex: 0, targetIndex: 1, widths: widths, spacing: 2) == 0)
        #expect(ShelfReorder.shift(forIndex: 0, pickedIndex: 1, targetIndex: 1, widths: widths, spacing: 2) == 0)
    }
}
