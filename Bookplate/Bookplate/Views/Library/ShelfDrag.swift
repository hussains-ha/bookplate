import SwiftUI

/// Shared state while a book is picked up, so it can leave its shelf and be dropped on another one.
/// Everything is in the library's coordinate space (`ShelfDrag.space`), which doesn't scroll.
@MainActor
@Observable
final class ShelfDrag {
    static let space = "library"

    struct Picked: Equatable {
        let book: Book
        let sourceShelfId: String
        /// Where the spine's bottom center and the finger were at pick-up.
        let spineStart: CGPoint
        let fingerStart: CGPoint
    }

    /// What a shelf reports about itself so drops can be placed on it.
    struct ShelfLayout: Equatable {
        /// The whole shelf: spine row and name plate.
        var frame: CGRect
        /// Where x = 0 of the spine row is right now (it moves as the shelf scrolls sideways).
        var rowOriginX: CGFloat
        /// Center of each spine in the row, from `rowOriginX`.
        var centers: [CGFloat]
        var isLocked: Bool
    }

    struct Target: Equatable {
        let shelfId: String
        let index: Int
    }

    var picked: Picked?
    var finger: CGPoint = .zero
    var shelves: [String: ShelfLayout] = [:]
    /// The visible part of the bookcase.
    var viewport: CGRect = .zero

    /// Shelves are this far apart; a finger in the gap counts as over the nearer shelf.
    static let shelfGap: CGFloat = 14

    var translation: CGSize {
        guard let picked else { return .zero }
        return CGSize(width: finger.x - picked.fingerStart.x, height: finger.y - picked.fingerStart.y)
    }

    /// The shelf under the finger, if it's in the visible bookcase.
    var hoveredShelfId: String? {
        guard picked != nil, viewport.contains(finger) else { return nil }
        return shelves.first { $0.value.frame.insetBy(dx: 0, dy: -Self.shelfGap / 2).contains(finger) }?.key
    }

    /// Where the book would land on another, unlocked shelf. Nil over its own shelf (which handles
    /// reordering itself), over a locked shelf, or outside every shelf.
    var target: Target? {
        guard let picked, let id = hoveredShelfId, id != picked.sourceShelfId,
              let layout = shelves[id], !layout.isLocked else { return nil }
        let index = layout.centers.filter { layout.rowOriginX + $0 < finger.x }.count
        return Target(shelfId: id, index: index)
    }
}
