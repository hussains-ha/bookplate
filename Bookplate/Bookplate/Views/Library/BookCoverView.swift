import SwiftUI

/// A book's front cover. Shows the generated cover while the image loads or if it fails.
struct BookCoverView: View {
    let book: Book
    var meta: BookMeta?

    var body: some View {
        AsyncImage(url: book.displayCoverURL(meta: meta), transaction: Transaction(animation: .easeIn(duration: 0.5))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            default:
                GeneratedCoverView(book: book)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(book.title)
    }
}

/// The front cover drawn from a book's title, author and generated color.
private struct GeneratedCoverView: View {
    let book: Book

    private var appearance: BookAppearance { BookAppearance(bookId: book.id) }

    var body: some View {
        VStack(spacing: 6) {
            Text(book.title)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            if let author = book.authors.first {
                Text(author)
                    .font(.system(size: 9, weight: .regular, design: .serif))
                    .multilineTextAlignment(.center)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(appearance.textColor)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(2 / 3, contentMode: .fit)
        .background(appearance.color)
        .clipShape(RoundedRectangle(cornerRadius: 3))
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
