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

    var picked: Picked? { didSet { refresh() } }
    var finger: CGPoint = .zero { didSet { refresh() } }
    var shelves: [String: ShelfLayout] = [:] { didSet { refresh() } }
    /// The visible part of the bookcase.
    var viewport: CGRect = .zero { didSet { refresh() } }

    /// The shelf under the finger, if it's in the visible bookcase.
    /// Stored (not computed) so shelves only re-render when it changes, not on every finger move.
    private(set) var hoveredShelfId: String?
    /// Where the book would land on another, unlocked shelf. Nil over its own shelf (which handles
    /// reordering itself), over a locked shelf, or outside every shelf.
    private(set) var target: Target?

    /// Shelves are this far apart; a finger in the gap counts as over the nearer shelf.
    static let shelfGap: CGFloat = 14

    var translation: CGSize {
        guard let picked else { return .zero }
        return CGSize(width: finger.x - picked.fingerStart.x, height: finger.y - picked.fingerStart.y)
    }

    private func refresh() {
        let hovered = Self.hoveredShelf(picked: picked, finger: finger, viewport: viewport, shelves: shelves)
        if hovered != hoveredShelfId { hoveredShelfId = hovered }
        let newTarget = Self.target(picked: picked, translation: translation, hovered: hovered, shelves: shelves)
        if newTarget != target { target = newTarget }
    }

    static func hoveredShelf(picked: Picked?, finger: CGPoint, viewport: CGRect, shelves: [String: ShelfLayout]) -> String? {
        guard picked != nil, viewport.contains(finger) else { return nil }
        return shelves.first { $0.value.frame.insetBy(dx: 0, dy: -shelfGap / 2).contains(finger) }?.key
    }

    /// Uses the dragged spine's center, like reordering within a shelf does, so the slot doesn't jump
    /// when the book crosses onto another shelf.
    static func target(picked: Picked?, translation: CGSize, hovered: String?, shelves: [String: ShelfLayout]) -> Target? {
        guard let picked, let id = hovered, id != picked.sourceShelfId,
              let layout = shelves[id], !layout.isLocked else { return nil }
        let center = picked.spineStart.x + translation.width
        return Target(shelfId: id, index: layout.centers.filter { layout.rowOriginX + $0 < center }.count)
    }
}
