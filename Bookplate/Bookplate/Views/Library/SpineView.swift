import SwiftUI

/// A book spine. Width follows page count; color is stable per book.
struct SpineView: View {
    let book: Book

    static let defaultWidth: CGFloat = 30
    static let minWidth: CGFloat = 20
    static let maxWidth: CGFloat = 54

    static func width(forPageCount pageCount: Int?) -> CGFloat {
        guard let pageCount, pageCount > 0 else { return defaultWidth }
        return min(max(CGFloat(pageCount) / 12, minWidth), maxWidth)
    }

    private var appearance: BookAppearance { BookAppearance(bookId: book.id) }

    var body: some View {
        Text(book.title)
            .font(.system(size: 9, weight: .semibold, design: .serif))
            .foregroundStyle(appearance.textColor.opacity(0.92))
            .lineLimit(1)
            .frame(width: appearance.spineHeight - 12)
            .rotationEffect(.degrees(-90))
            .frame(width: Self.width(forPageCount: book.pageCount), height: appearance.spineHeight)
            .background(appearance.color)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .accessibilityElement()
            .accessibilityLabel(book.title)
    }
}

#Preview {
    HStack(alignment: .bottom, spacing: 2) {
        ForEach(Book.mocks) { SpineView(book: $0) }
    }
    .padding()
    .background(Theme.wood)
}
