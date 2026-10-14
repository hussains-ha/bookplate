import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store

    @State private var query = ""
    @State private var showingAddBook = false

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
                    ForEach(store.bookshelf.shelves) { shelf in
                        ShelfView(shelf: shelf, books: store.books(on: shelf, matching: query))
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Theme.wood, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingAddBook) {
            AddBookView(defaultShelfId: store.defaultShelfId)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bookplate")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.brown)
                Text("\(store.bookshelf.name) · \(store.books.count) books")
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedText)
            }
            Spacer()
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

#Preview {
    LibraryView()
        .environment(LibraryStore.sample())
}
