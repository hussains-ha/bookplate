import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store

    @State private var query = ""
    @State private var filter: LibraryFilter = .all
    /// Per-shelf display order for this session; missing means Custom.
    @State private var shelfSorts: [String: ShelfSort] = [:]
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

            if store.isLibraryEmpty {
                emptyLibrary
            } else {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.mutedText)
                    TextField("Title, author, or tag", text: $query)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mutedText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                    filterMenu
                }
                .authFieldStyle()

                if isNarrowed, visibleShelves.isEmpty {
                    noMatches
                } else {
                    bookcase
                }
            }
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

    private var visibleShelves: [LibraryStore.VisibleShelf] { store.visibleShelves(matching: query, filter: filter) }

    /// True while search or the filter hides some books, so shelf order on screen isn't the real order.
    private var isNarrowed: Bool { LibraryStore.isSearching(query) || filter != .all }

    private var filterMenu: some View {
        Menu {
            Section {
                filterRow(.all)
            }
            Section {
                ForEach(LibraryFilter.statuses, id: \.self) { filterRow(.status($0)) }
                filterRow(.favorites)
            }
            let tags = store.allTags
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.self) { filterRow(.tag($0)) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(filter.title).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filter == .all ? Theme.mutedText : Theme.brown)
            .frame(maxWidth: 140, alignment: .trailing)
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityLabel("Filter: \(filter.title)")
        // A tag that no book has any more can't stay selected.
        .onChange(of: store.allTags) { filter = store.resolved(filter) }
    }

    private func filterRow(_ option: LibraryFilter) -> some View {
        Button { filter = option } label: {
            let text = "\(option.title) (\(store.count(for: option)))"
            if filter == option { Label(text, systemImage: "checkmark") } else { Text(text) }
        }
    }

    private var bookcase: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(visibleShelves, id: \.shelf.id) { visible in
                    let shelf = visible.shelf
                    // The shelf's place in the whole bookcase, not in the (possibly filtered) list on screen.
                    let index = store.bookshelf.shelves.firstIndex { $0.id == shelf.id } ?? 0
                    let sort = shelfSorts[shelf.id] ?? .custom
                    ShelfView(
                        shelf: shelf,
                        books: sort.apply(to: visible.books) { store.meta(for: $0.id)?.rating },
                        isReorderEnabled: !isNarrowed && sort == .custom,
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
                        onDelete: store.bookshelf.shelves.count > 1 ? { shelfToDelete = PendingDeletion(shelf: shelf, deletion: store.shelfDeletion(shelf.id)) } : nil,
                        sort: sort,
                        onSort: { new in withAnimation(.snappy) { shelfSorts[shelf.id] = new == .custom ? nil : new } }
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

    private var emptyLibrary: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brown.opacity(0.6))
            Text("Your library is empty")
                .font(Theme.title(22))
                .foregroundStyle(Theme.brown)
            Text("Add your first book to start filling your shelves.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center)
            Button { showingAddBook = true } label: {
                Label("Add a book", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.brown, in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesMessage: String {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = "\u{2018}\(search)\u{2019}"
        switch (LibraryStore.isSearching(query), filter) {
        case (true, .all): return "No matches for \(quoted)."
        case (true, _): return "No matches for \(quoted) in \(filter.title)."
        default: return "No books in \(filter.title)."
        }
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Theme.brown.opacity(0.5))
            Text(noMatchesMessage)
                .font(.headline)
                .foregroundStyle(Theme.brown)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

#Preview("Empty library") {
    LibraryView()
        .environment(LibraryStore(
            books: [], metas: [],
            bookshelf: Bookshelf(id: "preview", name: "My Library",
                                 shelves: [Shelf(id: "s", name: "To Read", bookIds: [])], appearance: .classic)))
}
