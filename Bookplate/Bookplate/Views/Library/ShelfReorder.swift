import CoreGraphics

/// Pure layout math for dragging a spine to a new spot on a shelf.
/// Spines sit in a row (in shelf order) separated by `spacing`, starting at x = 0.
enum ShelfReorder {
    /// Horizontal center of the spine at `index` in the original layout.
    static func center(ofIndex index: Int, widths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let leading = widths[..<index].reduce(0) { $0 + $1 + spacing }
        return leading + widths[index] / 2
    }

    /// The index the picked spine would take if dropped with its center at `draggedCenter`:
    /// the number of other spines whose original center is to its left.
    static func targetIndex(draggedCenter: CGFloat, pickedIndex: Int, widths: [CGFloat], spacing: CGFloat) -> Int {
        widths.indices.filter { $0 != pickedIndex }.reduce(0) { count, index in
            center(ofIndex: index, widths: widths, spacing: spacing) < draggedCenter ? count + 1 : count
        }
    }

    /// How far the picked spine's slot has moved from its original spot once it targets `targetIndex`.
    static func slotOffset(pickedIndex: Int, targetIndex: Int, widths: [CGFloat], spacing: CGFloat) -> CGFloat {
        if targetIndex > pickedIndex {
            return widths[(pickedIndex + 1)...targetIndex].reduce(0) { $0 + $1 + spacing }
        } else if targetIndex < pickedIndex {
            return -widths[targetIndex..<pickedIndex].reduce(0) { $0 + $1 + spacing }
        }
        return 0
    }

    /// How far another spine slides to open the gap: toward the picked spine's old spot by one slot.
    static func shift(forIndex index: Int, pickedIndex: Int, targetIndex: Int, widths: [CGFloat], spacing: CGFloat) -> CGFloat {
        let slot = widths[pickedIndex] + spacing
        if pickedIndex < targetIndex, index > pickedIndex, index <= targetIndex { return -slot }
        if targetIndex < pickedIndex, index >= targetIndex, index < pickedIndex { return slot }
        return 0
    }
}
