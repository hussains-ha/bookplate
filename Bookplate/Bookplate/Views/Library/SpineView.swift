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

    /// Deterministic (unlike `hashValue`) so a book keeps its look across launches.
    private var seed: Int {
        book.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
    }

    private var color: Color { Theme.spineColors[seed % Theme.spineColors.count] }
    private var height: CGFloat { 92 + CGFloat(seed % 5) * 6 }

    private var textColor: Color {
        color == Theme.spineColors[5] ? Theme.brown : .white
    }

    var body: some View {
        Text(book.title)
            .font(.system(size: 9, weight: .semibold, design: .serif))
            .foregroundStyle(textColor.opacity(0.92))
            .lineLimit(1)
            .frame(width: height - 12)
            .rotationEffect(.degrees(-90))
            .frame(width: Self.width(forPageCount: book.pageCount), height: height)
            .background(color)
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
