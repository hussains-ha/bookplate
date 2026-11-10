import SwiftUI

/// A book's front cover. Shows the generated cover while the image loads or if it fails.
struct BookCoverView: View {
    let book: Book
    var meta: BookMeta?

    var body: some View {
        let url = book.displayCoverURL(meta: meta)
        AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.5))) { phase in
            switch phase {
            case .success(let image):
                // Always the 2:3 book shape, so a photo of any shape doesn't shift the layout.
                Color.clear
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    // Same drop shadow as the generated cover, which draws its own.
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 3)
                    .transition(.opacity)
            default:
                GeneratedCoverView(book: book)
            }
        }
        // A new identity per URL, so clearing a custom cover drops the old image instead of keeping it.
        .id(url)
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
