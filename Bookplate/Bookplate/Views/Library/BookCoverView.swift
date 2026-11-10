import SwiftUI

/// A book's front cover. Shows the generated cover while the image loads or if it fails.
struct BookCoverView: View {
    let book: Book
    var meta: BookMeta?

    var body: some View {
        let url = book.displayCoverURL(meta: meta)
        // Always the 2:3 book shape, so a photo of any shape doesn't shift the layout.
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                CachedImage(url: url) { image in
                    Color.clear
                        .overlay { image.resizable().scaledToFill() }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        // Same drop shadow as the generated cover, which draws its own.
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 3)
                } placeholder: {
                    GeneratedCoverView(book: book)
                }
            }
        .accessibilityElement()
        .accessibilityLabel(book.title)
    }
}

#Preview {
    let custom = BookMeta(
        bookId: Book.mock.id, status: BookMeta.Status.read, rating: nil, notes: nil, notePhotos: [], tags: [],
        customCover: URL(string: "https://covers.openlibrary.org/b/isbn/9780441013593-L.jpg?default=false"),
        addedDate: .now, startedDate: nil, finishedDate: nil
    )
    HStack(spacing: 12) {
        BookCoverView(book: .mock)
        BookCoverView(book: .mock, meta: custom)
        BookCoverView(book: Book.mocks[3])
    }
    .frame(height: 180)
    .padding()
    .background(Theme.background)
}
