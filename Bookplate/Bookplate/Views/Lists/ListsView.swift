import SwiftUI

/// The Lists tab: every list as a collapsible card with its books.
struct ListsView: View {
    @Environment(LibraryStore.self) private var store

    @State private var query = ""
    @State private var collapsed: Set<String> = []
    @State private var showingAddList = false
    @State private var listToDelete: BookList?
    @State private var selectedBook: Book?

    private var isSearching: Bool { LibraryStore.isSearching(query) }

    var body: some View {
        let visible = store.visibleLists(matching: query)
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if store.lists.isEmpty {
                        emptyState
                    } else if visible.isEmpty {
                        noMatches
                    } else {
                        ForEach(visible) { item in
                            ListCard(
                                item: item,
                                // Searching shows every match, so nothing stays folded away.
                                isExpanded: isSearching || !collapsed.contains(item.id),
                                canCollapse: !isSearching,
                                onToggle: { toggle(item.id) },
                                onSelect: { selectedBook = $0 },
                                onRemove: { book in
                                    withAnimation(.snappy) { store.setBook(book.id, inList: item.id, to: false) }
                                },
                                onDelete: { listToDelete = item.list }
                            )
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Lists")
            .searchable(text: $query, prompt: "List, title, or author")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAddList = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New list")
                }
            }
        }
        .tint(Theme.brown)
        .sheet(isPresented: $showingAddList) { AddListView() }
        .sheet(item: $selectedBook) { book in BookDetailView(bookId: book.id) }
        .alert(deleteTitle, isPresented: Binding(get: { listToDelete != nil }, set: { if !$0 { listToDelete = nil } }),
               presenting: listToDelete) { list in
            Button("Delete", role: .destructive) {
                withAnimation(.snappy) { store.deleteList(list.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The books stay in your library.")
        }
    }

    private var deleteTitle: String {
        listToDelete.map { "Delete “\($0.name)”?" } ?? "Delete list?"
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy) {
            if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.mutedText)
            Text("No lists yet")
                .font(Theme.title(22))
                .foregroundStyle(Theme.brown)
            Text("Make a list, then add books to it from a book's details.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center)
            Button("New List") { showingAddList = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brown)
        }
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(Theme.mutedText)
            Text("No lists or books match “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }
}

/// One list: a header that folds the card, then its books.
private struct ListCard: View {
    let item: LibraryStore.VisibleList
    let isExpanded: Bool
    let canCollapse: Bool
    let onToggle: () -> Void
    let onSelect: (Book) -> Void
    let onRemove: (Book) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().overlay(Theme.mutedText.opacity(0.3))
                if item.books.isEmpty {
                    Text("No books yet. Add books from a book's details.")
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    ForEach(item.books) { book in
                        row(book)
                        if book.id != item.books.last?.id {
                            Divider().overlay(Theme.mutedText.opacity(0.2)).padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.mutedText.opacity(0.2)))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(canCollapse ? 1 : 0.3)
                    Text(item.list.name)
                        .font(Theme.title(18))
                        .lineLimit(1)
                    Text("\(item.list.bookIds.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.background, in: Capsule())
                        .accessibilityLabel("\(item.list.bookIds.count) books")
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCollapse)
            .accessibilityLabel("\(item.list.name), \(item.list.bookIds.count) books")
            .accessibilityHint(canCollapse ? (isExpanded ? "Collapses the list" : "Expands the list") : "")

            Menu {
                Button("Delete List", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(item.list.name)")
        }
        .foregroundStyle(Theme.brown)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 8)
    }

    private func row(_ book: Book) -> some View {
        HStack(spacing: 10) {
            Button { onSelect(book) } label: {
                HStack(spacing: 8) {
                    Text(book.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.brown)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(book.authors.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedText)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { onRemove(book) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.body)
                    .foregroundStyle(Theme.mutedText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(book.title) from \(item.list.name)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

#Preview {
    ListsView()
        .environment(LibraryStore.sample())
}
