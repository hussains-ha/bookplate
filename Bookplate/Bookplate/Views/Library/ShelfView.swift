import SwiftUI

/// One shelf: a label plate above a sideways-scrolling row of spines.
/// Press and hold a spine to pick it up, slide it to a new spot (on this shelf or another one), and let go to drop it.
struct ShelfView: View {
    let shelf: Shelf
    let books: [Book]
    /// Turn off while the books on screen aren't the shelf's real order (e.g. while searching).
    var isReorderEnabled = true
    var onToggleLock: () -> Void = {}
    var onSelect: (Book) -> Void = { _ in }
    var onMove: (_ bookId: String, _ toIndex: Int) -> Void = { _, _ in }
    /// Drop on another shelf.
    var onMoveToShelf: (_ bookId: String, _ shelfId: String, _ index: Int) -> Void = { _, _, _ in }
    /// Returns why the name was rejected, or nil once it's saved.
    var onRename: (String) -> LibraryStore.ShelfNameProblem? = { _ in nil }
    /// Nil when the shelf is already at the top (or bottom).
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    /// Nil for the last shelf, which can't be deleted.
    var onDelete: (() -> Void)?

    @Environment(ShelfDrag.self) private var drag

    static let spacing: CGFloat = 2
    private static let rowPadding: CGFloat = 12
    private static let holdDuration = 0.25
    private static let holdTolerance: CGFloat = 10
    private static let edgeZone: CGFloat = 44
    private static let maxScrollPerTick: CGFloat = 9

    @State private var targetIndex = 0
    @State private var pickupScrollX: CGFloat = 0
    @State private var metrics = ScrollMetrics()
    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var frame: CGRect = .zero
    @State private var rowFrame: CGRect = .zero
    @GestureState private var gestureActive = false
    @State private var draftName: String?
    @State private var renameProblem: LibraryStore.ShelfNameProblem?
    @FocusState private var isNameFocused: Bool
    /// Return ends editing even when the name is rejected; this keeps that from counting as "tapped away".
    @State private var keepEditingAfterSubmit = false

    private struct ScrollMetrics: Equatable {
        var offsetX: CGFloat = 0
        var contentWidth: CGFloat = 0
        var visibleWidth: CGFloat = 0
    }

    private var canReorder: Bool { isReorderEnabled && !shelf.isLocked }
    private var widths: [CGFloat] { books.map { SpineView.width(forPageCount: $0.pageCount) } }
    /// The book picked up from this shelf, if any.
    private var pickedId: String? { drag.picked?.sourceShelfId == shelf.id ? drag.picked?.book.id : nil }
    private var pickedIndex: Int? { books.firstIndex { $0.id == pickedId } }
    private var isHovered: Bool { drag.hoveredShelfId == shelf.id }
    /// Where a book from another shelf would land here.
    private var incomingIndex: Int? { drag.target?.shelfId == shelf.id ? drag.target?.index : nil }
    private var fingerX: CGFloat { drag.finger.x - frame.minX }

    /// How far the picked spine has traveled along this shelf, counting the shelf scrolling underneath it.
    private var travel: CGFloat { drag.translation.width + (metrics.offsetX - pickupScrollX) }

    private var layout: ShelfDrag.ShelfLayout {
        ShelfDrag.ShelfLayout(
            frame: frame,
            rowOriginX: rowFrame.minX + Self.rowPadding - metrics.offsetX,
            centers: widths.indices.map { ShelfReorder.center(ofIndex: $0, widths: widths, spacing: Self.spacing) },
            isLocked: !canReorder
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: Self.spacing) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        spineCell(book, at: index)
                    }
                }
                .padding(.horizontal, Self.rowPadding)
                .frame(minHeight: 112, alignment: .bottom)
                .overlay(alignment: .bottomLeading) { incomingPlaceholder }
            }
            .scrollPosition($scrollPosition)
            .scrollDisabled(drag.picked != nil)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(offsetX: geometry.contentOffset.x,
                              contentWidth: geometry.contentSize.width,
                              visibleWidth: geometry.visibleRect.width)
            } action: { _, new in
                metrics = new
                if pickedId != nil { updateTarget() }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShelfDrag.space)) } action: { rowFrame = $0 }

            HStack {
                nameLabel
                if let renameProblem {
                    Text(renameProblem.message)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShelfDrag.space)) } action: { frame = $0 }
        .onChange(of: layout, initial: true) { _, new in drag.shelves[shelf.id] = new }
        .onDisappear { drag.shelves[shelf.id] = nil }
        .sensoryFeedback(.impact(weight: .medium), trigger: pickedId)
        .sensoryFeedback(.selection, trigger: incomingIndex) { _, new in new != nil }
        .onChange(of: gestureActive) { _, active in
            // Safety net: if the touch is interrupted, put the book back.
            if !active, pickedId != nil { finish(drop: false) }
        }
        .onChange(of: books.map(\.id)) {
            // The picked book left the shelf (or the shelf changed under the drag): put everything back.
            if pickedId != nil, pickedIndex == nil { finish(drop: false) }
        }
        .background {
            // Only the source shelf follows the finger, so other shelves don't re-render on every move.
            if pickedId != nil {
                Color.clear.onChange(of: drag.finger) { updateTarget() }
            }
        }
        .onChange(of: isHovered) { if pickedId != nil { updateTarget() } }
        .onDisappear {
            // Never leave a book floating (and every scroll view disabled) if this shelf goes away mid-drag.
            if pickedId != nil { drag.picked = nil }
        }
        .task(id: isHovered) { await autoScrollWhileHovered() }
    }

    // MARK: Name plate

    @ViewBuilder
    private var nameLabel: some View {
        if let draft = draftName {
            TextField("Shelf name", text: Binding(
                get: { draft },
                set: { newValue in
                    let capped = String(newValue.prefix(LibraryStore.maxShelfNameLength))
                    // The field re-sends its text when focus comes back; only a real edit clears the error.
                    guard capped != draftName else { return }
                    draftName = capped
                    renameProblem = nil
                }
            ))
            .focused($isNameFocused)
            // Focus once the field exists (setting it in the same update that inserts the field is unreliable).
            .onAppear { Task { isNameFocused = true } }
            .submitLabel(.done)
            .onSubmit(commitRename)
            .onKeyPress(.escape) {
                cancelRename()
                return .handled
            }
            .onChange(of: isNameFocused) { _, focused in
                // Tapping away cancels, like Escape.
                guard !focused else { return }
                if keepEditingAfterSubmit {
                    keepEditingAfterSubmit = false
                    Task { isNameFocused = true }
                } else {
                    cancelRename()
                }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.brown)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(minWidth: 90, maxWidth: 220)
            .background(Theme.label, in: RoundedRectangle(cornerRadius: 1))
            .accessibilityLabel("Shelf name")
            .accessibilityAction(.escape, cancelRename)
        } else {
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
            .contentShape(Rectangle())
            .onTapGesture(perform: startRename)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Tap to rename")
            .accessibilityAction(named: "Rename", startRename)
            .accessibilityAction(named: "Move Up") { onMoveUp?() }
            .accessibilityAction(named: "Move Down") { onMoveDown?() }
            .accessibilityAction(named: shelf.isLocked ? "Unlock Shelf" : "Lock Shelf", onToggleLock)
            .contextMenu {
                Button("Rename", systemImage: "pencil", action: startRename)
                if let onMoveUp {
                    Button("Move Up", systemImage: "arrow.up", action: onMoveUp)
                }
                if let onMoveDown {
                    Button("Move Down", systemImage: "arrow.down", action: onMoveDown)
                }
                Button(shelf.isLocked ? "Unlock Shelf" : "Lock Shelf",
                       systemImage: shelf.isLocked ? "lock.open" : "lock",
                       action: onToggleLock)
                if let onDelete {
                    Divider()
                    Button("Delete Shelf", systemImage: "trash", role: .destructive, action: onDelete)
                }
            }
        }
    }

    private func startRename() {
        renameProblem = nil
        keepEditingAfterSubmit = false
        draftName = shelf.name
    }

    private func commitRename() {
        guard let draft = draftName else { return }
        if let problem = onRename(draft) {
            renameProblem = problem
            keepEditingAfterSubmit = true     // keep the field open to fix the name
            AccessibilityNotification.Announcement(problem.message).post()
        } else {
            cancelRename()
        }
    }

    private func cancelRename() {
        draftName = nil
        renameProblem = nil
        keepEditingAfterSubmit = false
    }

    // MARK: Spines

    @ViewBuilder
    private func spineCell(_ book: Book, at index: Int) -> some View {
        let isPicked = book.id == pickedId
        ZStack(alignment: .bottom) {
            if isPicked, let picked = pickedIndex, isHovered {
                // The translucent placeholder marks where the book will land on this shelf.
                SpineView(book: book)
                    .opacity(0.3)
                    .offset(x: ShelfReorder.slotOffset(pickedIndex: picked, targetIndex: targetIndex,
                                                       widths: widths, spacing: Self.spacing))
            }
            // The picked spine itself floats above the whole library (see LibraryView); its cell stays
            // here, invisible, so the gesture keeps running.
            SpineView(book: book)
                .opacity(isPicked ? 0 : 1)
                .offset(x: isPicked ? 0 : shiftForGap(at: index))
        }
        .zIndex(isPicked ? 1 : 0)
        .onTapGesture { if drag.picked == nil { onSelect(book) } }
        .accessibilityAddTraits(.isButton)
        .gesture(pickUpGesture(for: book, at: index), including: canReorder ? .all : .subviews)
    }

    private func shiftForGap(at index: Int) -> CGFloat {
        if let picked = pickedIndex {
            // Over another shelf, this shelf closes the gap: as if the book moved to the end.
            let target = isHovered ? targetIndex : widths.count - 1
            return ShelfReorder.shift(forIndex: index, pickedIndex: picked, targetIndex: target,
                                      widths: widths, spacing: Self.spacing)
        }
        if let incoming = incomingIndex.map({ min($0, widths.count) }), index >= incoming, let book = drag.picked?.book {
            return SpineView.width(forPageCount: book.pageCount) + Self.spacing
        }
        return 0
    }

    /// The translucent spot where a book from another shelf would land.
    @ViewBuilder
    private var incomingPlaceholder: some View {
        if let index = incomingIndex.map({ min($0, widths.count) }), let book = drag.picked?.book {
            let leading = widths[..<index].reduce(0) { $0 + $1 + Self.spacing }
            SpineView(book: book)
                .opacity(0.3)
                .offset(x: Self.rowPadding + leading)
                .allowsHitTesting(false)
        }
    }

    // MARK: Gesture

    private func pickUpGesture(for book: Book, at index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: Self.holdTolerance)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(ShelfDrag.space)))
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in
                guard case .second(true, let drag) = value, let drag else { return }
                if self.drag.picked == nil { pickUp(book, at: index, finger: drag.startLocation) }
                guard pickedId == book.id else { return }
                self.drag.finger = drag.location
            }
            .onEnded { value in
                guard pickedId == book.id else { return }
                guard case .second(true, _) = value else { return finish(drop: false) }
                finish(drop: true)
            }
    }

    private func pickUp(_ book: Book, at index: Int, finger: CGPoint) {
        pickupScrollX = metrics.offsetX
        targetIndex = index
        let center = ShelfReorder.center(ofIndex: index, widths: widths, spacing: Self.spacing)
        let spineStart = CGPoint(x: rowFrame.minX + Self.rowPadding + center - metrics.offsetX, y: rowFrame.maxY)
        drag.finger = finger
        withAnimation(.snappy(duration: 0.2)) {
            drag.picked = ShelfDrag.Picked(book: book, sourceShelfId: shelf.id, spineStart: spineStart, fingerStart: finger)
        }
    }

    private func updateTarget() {
        guard let picked = pickedIndex, isHovered else { return }
        let center = ShelfReorder.center(ofIndex: picked, widths: widths, spacing: Self.spacing) + travel
        let target = ShelfReorder.targetIndex(draggedCenter: center, pickedIndex: picked,
                                              widths: widths, spacing: Self.spacing)
        if target != targetIndex {
            withAnimation(.snappy(duration: 0.2)) { targetIndex = target }
        }
    }

    private func finish(drop: Bool) {
        let target = drag.target
        let overThisShelf = isHovered
        // Move and put the book down in one animation, so neighbors settle instead of jumping.
        withAnimation(.snappy(duration: 0.2)) {
            if drop, let picked = pickedIndex {
                let bookId = books[picked].id
                if overThisShelf, targetIndex != picked {
                    onMove(bookId, targetIndex)
                } else if let target {
                    onMoveToShelf(bookId, target.shelfId, target.index)
                }
                // Anywhere else (a locked shelf, outside the bookcase): the book goes back.
            }
            drag.picked = nil
        }
    }

    // MARK: Auto-scroll

    /// Scrolls the shelf sideways while a picked-up book is held near its left or right edge.
    /// Waits for the finger to move first, so a book held still right after pick-up doesn't start scrolling.
    private func autoScrollWhileHovered() async {
        guard isHovered, drag.picked != nil else { return }
        // Track the offset here instead of re-reading it each tick, so a lagging scroll report can't slow the scroll.
        var offset = metrics.offsetX
        while !Task.isCancelled {
            if drag.translation != .zero {
                let depth: CGFloat
                if fingerX < Self.edgeZone {
                    depth = -(Self.edgeZone - fingerX) / Self.edgeZone
                } else if fingerX > frame.width - Self.edgeZone {
                    depth = (fingerX - (frame.width - Self.edgeZone)) / Self.edgeZone
                } else {
                    depth = 0
                }
                if depth != 0 {
                    let maxX = max(0, metrics.contentWidth - metrics.visibleWidth)
                    offset = min(max(offset + min(max(depth, -1), 1) * Self.maxScrollPerTick, 0), maxX)
                    scrollPosition.scrollTo(x: offset)
                }
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}

#Preview {
    ShelfView(shelf: .mock, books: Book.mocks)
        .background(Theme.wood)
        .environment(ShelfDrag())
}
