import SwiftUI

/// One shelf: a label plate above a sideways-scrolling row of spines.
struct ShelfView: View {
    let shelf: Shelf
    let books: [Book]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(books) { SpineView(book: $0) }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 112, alignment: .bottom)
            }

            HStack {
                Text(shelf.name)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.brown)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.label, in: RoundedRectangle(cornerRadius: 1))
                Spacer()
                Text("\(books.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.label.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Theme.woodShelf)
        }
    }
}

#Preview {
    ShelfView(shelf: .mock, books: Book.mocks)
        .background(Theme.wood)
}
