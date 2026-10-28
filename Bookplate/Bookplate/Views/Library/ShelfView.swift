import SwiftUI

/// One shelf: a label plate above a sideways-scrolling row of spines.
/// Press and hold a spine to pick it up, slide it to a new spot, and let go to drop it.
struct ShelfView: View {
    let shelf: Shelf
    let books: [Book]
    /// Turn off while the books on screen aren't the shelf's real order (e.g. while searching).
    var isReorderEnabled = true
    var onToggleLock: () -> Void = {}
    var onMove: (_ bookId: String, _ toIndex: Int) -> Void = { _, _ in }

    private static let spacing: CGFloat = 2
    private static let holdDuration = 0.25
    private static let holdTolerance: CGFloat = 10
    private static let edgeZone: CGFloat = 44
    private static let maxScrollPerTick: CGFloat = 9

    @State private var pickedId: String?
    @State private var targetIndex = 0
    @State private var fingerX: CGFloat = 0
    @State private var startFingerX: CGFloat?
    @State private var pickupScrollX: CGFloat = 0
    @State private var metrics = ScrollMetrics()
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var shelfSize: CGSize = .zero
    @GestureState private var gestureActive = false

    private struct ScrollMetrics: Equatable {
        var offsetX: CGFloat = 0
        var contentWidth: CGFloat = 0
        var visibleWidth: CGFloat = 0
    }

    private var canReorder: Bool { isReorderEnabled && !shelf.isLocked }
    private var widths: [CGFloat] { books.map { SpineView.width(forPageCount: $0.pageCount) } }
    private var pickedIndex: Int? { books.firstIndex { $0.id == pickedId } }

    /// How far the picked spine has traveled, counting the shelf scrolling underneath it.
    private var travel: CGFloat {
        (fingerX - (startFingerX ?? fingerX)) + (metrics.offsetX - pickupScrollX)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: Self.spacing) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        spineCell(book, at: index)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 112, alignment: .bottom)
            }
            .scrollPosition($scrollPosition)
            .scrollDisabled(pickedId != nil)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(offsetX: geometry.contentOffset.x,
                              contentWidth: geometry.contentSize.width,
                              visibleWidth: geometry.visibleRect.width)
            } action: { _, new in
                metrics = new
            }

            HStack {
                HStack(spacing: 3) {
                    if shelf.isLocked {
                        Image(systemName: "lock.fill").accessibilityLabel("Locked")
                    }
                    Text(shelf.name)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.brown)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Theme.label, in: RoundedRectangle(cornerRadius: 1))
                .contextMenu {
                    Button(shelf.isLocked ? "Unlock Shelf" : "Lock Shelf",
                           systemImage: shelf.isLocked ? "lock.open" : "lock",
                           action: onToggleLock)
                }
                Spacer()
                Text("\(books.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.label.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Theme.woodShelf)
        }
        .coordinateSpace(.named("shelf"))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { shelfSize = $0 }
        .sensoryFeedback(.impact(weight: .medium), trigger: pickedId)
        .onChange(of: gestureActive) { _, active in
            // Safety net: if the touch is interrupted, put the book back.
            if !active, pickedId != nil { finish(drop: false) }
        }
        .task(id: pickedId) { await autoScrollWhilePicked() }
    }

    // MARK: Spines

    @ViewBuilder
    private func spineCell(_ book: Book, at index: Int) -> some View {
        let isPicked = book.id == pickedId
        ZStack(alignment: .bottom) {
            if isPicked, let picked = pickedIndex {
                // The translucent placeholder marks where the book will land.
                SpineView(book: book)
                    .opacity(0.3)
                    .offset(x: ShelfReorder.slotOffset(pickedIndex: picked, targetIndex: targetIndex,
                                                       widths: widths, spacing: Self.spacing))
            }
            if isPicked {
                SpineView(book: book)
                    .scaleEffect(1.08, anchor: .bottom)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                    .offset(x: travel, y: -6)
                    .transaction(value: travel) { $0.animation = nil }
            } else {
                SpineView(book: book)
                    .offset(x: shiftForGap(at: index))
            }
        }
        .zIndex(isPicked ? 1 : 0)
        .gesture(pickUpGesture(for: book, at: index), including: canReorder ? .all : .subviews)
    }

    private func shiftForGap(at index: Int) -> CGFloat {
        guard let picked = pickedIndex else { return 0 }
        return ShelfReorder.shift(forIndex: index, pickedIndex: picked, targetIndex: targetIndex,
                                  widths: widths, spacing: Self.spacing)
    }

    // MARK: Gesture

    private func pickUpGesture(for book: Book, at index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: Self.holdTolerance)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("shelf")))
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if pickedId == nil { pickUp(book, at: index) }
                guard pickedId == book.id, let drag else { return }
                if startFingerX == nil { startFingerX = drag.startLocation.x }
                fingerX = drag.location.x
                updateTarget()
            }
            .onEnded { value in
                guard pickedId == book.id else { return }
                guard case .second(true, let drag) = value else { return finish(drop: false) }
                let inside = drag.map { CGRect(origin: .zero, size: shelfSize).contains($0.location) } ?? true
                finish(drop: inside)
            }
    }

    private func pickUp(_ book: Book, at index: Int) {
        startFingerX = nil
        pickupScrollX = metrics.offsetX
        targetIndex = index
        withAnimation(.snappy(duration: 0.2)) { pickedId = book.id }
    }

    private func updateTarget() {
        guard let picked = pickedIndex else { return }
        let center = ShelfReorder.center(ofIndex: picked, widths: widths, spacing: Self.spacing) + travel
        let target = ShelfReorder.targetIndex(draggedCenter: center, pickedIndex: picked,
                                              widths: widths, spacing: Self.spacing)
        if target != targetIndex {
            withAnimation(.snappy(duration: 0.2)) { targetIndex = target }
        }
    }

    private func finish(drop: Bool) {
        if drop, let picked = pickedIndex, targetIndex != picked {
            onMove(books[picked].id, targetIndex)
        }
        withAnimation(.snappy(duration: 0.2)) { pickedId = nil }
        startFingerX = nil
    }

    // MARK: Auto-scroll

    /// Scrolls the shelf sideways while a picked-up book is held near its left or right edge.
    private func autoScrollWhilePicked() async {
        guard pickedId != nil else { return }
        while !Task.isCancelled {
            let depth: CGFloat
            if fingerX < Self.edgeZone {
                depth = -(Self.edgeZone - fingerX) / Self.edgeZone
            } else if fingerX > shelfSize.width - Self.edgeZone {
                depth = (fingerX - (shelfSize.width - Self.edgeZone)) / Self.edgeZone
            } else {
                depth = 0
            }
            if depth != 0 {
                let maxX = max(0, metrics.contentWidth - metrics.visibleWidth)
                let newX = min(max(metrics.offsetX + min(max(depth, -1), 1) * Self.maxScrollPerTick, 0), maxX)
                scrollPosition.scrollTo(x: newX)
                metrics.offsetX = newX
                updateTarget()
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}

#Preview {
    ShelfView(shelf: .mock, books: Book.mocks)
        .background(Theme.wood)
}
