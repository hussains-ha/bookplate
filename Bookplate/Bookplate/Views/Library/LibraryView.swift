import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store

    @State private var query = ""
    @State private var showingAddBook = false
    @State private var showingAddShelf = false
    @State private var selectedBook: Book?
    @State private var shelfToDelete: Shelf?

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
                            onRename: { store.renameShelf(shelf.id, to: $0) },
                            onMoveUp: index > 0 ? { withAnimation(.snappy) { store.moveShelf(shelf.id, to: index - 1) } } : nil,
                            onMoveDown: index < store.bookshelf.shelves.count - 1
                                ? { withAnimation(.snappy) { store.moveShelf(shelf.id, to: index + 1) } } : nil,
                            onDelete: store.bookshelf.shelves.count > 1 ? { shelfToDelete = shelf } : nil
                        )
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Theme.wood, in: RoundedRectangle(cornerRadius: 6))
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
               presenting: shelfToDelete) { shelf in
            if case .allowed = store.shelfDeletion(shelf.id) {
                Button("Delete", role: .destructive) {
                    withAnimation(.snappy) { _ = store.deleteShelf(shelf.id) }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { shelf in
            Text(deleteMessage(for: shelf))
        }
        .sheet(item: $selectedBook) { book in
            BookDetailView(bookId: book.id)
        }
    }

    private var deleteTitle: String {
        guard let shelf = shelfToDelete else { return "" }
        if case .allowed = store.shelfDeletion(shelf.id) { return "Delete \u{201C}\(shelf.name)\u{201D}?" }
        return "Can\u{2019}t Delete Shelf"
    }

    private func deleteMessage(for shelf: Shelf) -> String {
        switch store.shelfDeletion(shelf.id) {
        case .allowed(let target?):
            let count = shelf.bookIds.count
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
