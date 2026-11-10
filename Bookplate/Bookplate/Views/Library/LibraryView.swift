import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store

    @State private var query = ""
    @State private var showingAddBook = false
    @State private var showingAddShelf = false
    @State private var selectedBook: Book?
    @State private var shelfToDelete: PendingDeletion?
    @State private var drag = ShelfDrag()
    @State private var libraryScroll = ScrollPosition(edge: .top)
    @State private var libraryMetrics = LibraryScrollMetrics()

    /// Worked out once when the prompt opens, so it doesn't change while the prompt closes.
    private struct PendingDeletion {
        let shelf: Shelf
        let deletion: LibraryStore.ShelfDeletion?
    }

    private struct LibraryScrollMetrics: Equatable {
        var offsetY: CGFloat = 0
        var maxOffsetY: CGFloat = 0
    }

    private static let edgeZone: CGFloat = 60
    private static let maxScrollPerTick: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedText)
                TextField("Title or author", text: $query)
            }
            .authFieldStyle()

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(store.bookshelf.shelves.enumerated()), id: \.element.id) { index, shelf in
                        ShelfView(
                            shelf: shelf,
                            books: store.books(on: shelf, matching: query),
                            isReorderEnabled: query.isEmpty,
                            onToggleLock: { store.setLocked(!shelf.isLocked, onShelf: shelf.id) },
                            onSelect: { selectedBook = $0 },
                            onMove: { bookId, to in store.moveBook(bookId, onShelf: shelf.id, to: to) },
                            onMoveToShelf: { bookId, targetId, to in
                                store.moveBook(bookId, from: shelf.id, toShelf: targetId, at: to)
                            },
                            onRename: { store.renameShelf(shelf.id, to: $0) },
                            onMoveUp: index > 0 ? { withAnimation(.snappy) { store.moveShelf(shelf.id, to: index - 1) } } : nil,
                            onMoveDown: index < store.bookshelf.shelves.count - 1
                                ? { withAnimation(.snappy) { store.moveShelf(shelf.id, to: index + 1) } } : nil,
                            onDelete: store.bookshelf.shelves.count > 1 ? { shelfToDelete = PendingDeletion(shelf: shelf, deletion: store.shelfDeletion(shelf.id)) } : nil
                        )
                    }
                }
                .padding(.vertical, 12)
            }
            // Room to scroll the last shelf clear of the floating tab bar and the undo toast.
            .contentMargins(.bottom, 64, for: .scrollContent)
            .scrollPosition($libraryScroll)
            .scrollDisabled(drag.picked != nil)
            .onScrollGeometryChange(for: LibraryScrollMetrics.self) { geometry in
                LibraryScrollMetrics(offsetY: geometry.contentOffset.y,
                                     maxOffsetY: max(0, geometry.contentSize.height - geometry.visibleRect.height))
            } action: { _, new in libraryMetrics = new }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShelfDrag.space)) } action: { drag.viewport = $0 }
            .background(Theme.wood, in: RoundedRectangle(cornerRadius: 6))
        }
        .coordinateSpace(.named(ShelfDrag.space))
        .overlay(alignment: .topLeading) { FloatingSpine() }
        .environment(drag)
        .task(id: drag.picked?.book.id) { await autoScrollWhileDragging() }
        .overlay(alignment: .bottom) {
            UndoToast().padding(.bottom, 8)
        }
        // Tapping a blank spot ends editing (e.g. cancels a shelf rename). On a background layer, so taps
        // inside text fields, spines and plates never reach it.
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: endEditing)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingAddBook) {
            AddBookView(defaultShelfId: store.defaultShelfId)
        }
        .sheet(isPresented: $showingAddShelf) {
            AddShelfView()
        }
        .alert(deleteTitle, isPresented: Binding(get: { shelfToDelete != nil }, set: { if !$0 { shelfToDelete = nil } }),
               presenting: shelfToDelete) { pending in
            if case .allowed = pending.deletion {
                Button("Delete", role: .destructive) {
                    withAnimation(.snappy) { _ = store.deleteShelf(pending.shelf.id) }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { pending in
            Text(deleteMessage(for: pending))
        }
        .sheet(item: $selectedBook) { book in
            BookDetailView(bookId: book.id)
        }
    }

    // MARK: Dragging between shelves

    /// Scrolls the bookcase up or down while a picked-up book is held near its top or bottom edge.
    private func autoScrollWhileDragging() async {
        guard drag.picked != nil else { return }
        var offset = libraryMetrics.offsetY
        while !Task.isCancelled, drag.picked != nil {
            let y = drag.finger.y, top = drag.viewport.minY, bottom = drag.viewport.maxY
            let depth: CGFloat
            if drag.translation == .zero {
                depth = 0
            } else if y < top + Self.edgeZone {
                depth = -(top + Self.edgeZone - y) / Self.edgeZone
            } else if y > bottom - Self.edgeZone {
                depth = (y - (bottom - Self.edgeZone)) / Self.edgeZone
            } else {
                depth = 0
            }
            if depth != 0 {
                offset = min(max(offset + min(max(depth, -1), 1) * Self.maxScrollPerTick, 0), libraryMetrics.maxOffsetY)
                libraryScroll.scrollTo(y: offset)
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private var deleteTitle: String {
        guard let pending = shelfToDelete else { return "" }
        if case .allowed = pending.deletion { return "Delete \u{201C}\(pending.shelf.name)\u{201D}?" }
        return "Can\u{2019}t Delete Shelf"
    }

    private func deleteMessage(for pending: PendingDeletion) -> String {
        switch pending.deletion {
        case .allowed(let target?):
            // Books already on the target aren't moved.
            let count = pending.shelf.bookIds.filter { !target.bookIds.contains($0) }.count
            guard count > 0 else { return "Its books are already on \u{201C}\(target.name)\u{201D}. No books are removed from your library." }
            return "Its \(count) \(count == 1 ? "book" : "books") will move to \u{201C}\(target.name)\u{201D}. No books are removed from your library."
        case .allowed(nil):
            return "This shelf is empty."
        case .lastShelf:
            return "Your bookcase needs at least one shelf."
        case .noShelfForBooks:
            return "Its books need somewhere to go, but every other shelf is locked. Unlock a shelf first."
        case nil:
            return ""
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bookplate")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.brown)
                Text("\(store.bookshelf.name) · \(store.books.count) \(store.books.count == 1 ? "book" : "books")")
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedText)
            }
            Spacer()
            Menu {
                Button("New Shelf", systemImage: "rectangle.stack.badge.plus") { showingAddShelf = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(Theme.brown)
                    .frame(width: 40, height: 40)
                    .background(Theme.brown.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("Library options")
            Button { showingAddBook = true } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.brown, in: Circle())
            }
            .accessibilityLabel("Add book")
        }
        .padding(.top, 8)
    }
}

/// The picked-up book, drawn above every shelf so it can travel between them.
/// Its own view, so following the finger re-renders only this, not the whole library.
private struct FloatingSpine: View {
    @Environment(ShelfDrag.self) private var drag

    var body: some View {
        if let picked = drag.picked {
            let height = BookAppearance(bookId: picked.book.id).spineHeight
            SpineView(book: picked.book)
                .scaleEffect(1.08, anchor: .bottom)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                .position(x: picked.spineStart.x + drag.translation.width,
                          y: picked.spineStart.y - height / 2 - 6 + drag.translation.height)
                .allowsHitTesting(false)
        }
    }
}

/// Ends text editing anywhere on screen.
@MainActor
func endEditing() {
    #if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}

#Preview {
    LibraryView()
        .environment(LibraryStore.sample())
}
