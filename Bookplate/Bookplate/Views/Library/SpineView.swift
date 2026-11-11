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

    /// Optional so spines still draw where no store is provided (e.g. previews).
    @Environment(LibraryStore.self) private var store: LibraryStore?

    @Environment(\.bookcaseScale) private var scale
    @Environment(\.palette) private var palette

    private var appearance: BookAppearance { BookAppearance(book: book) }
    private var status: String? { store?.meta(for: book.id)?.status }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BookAppearance.displayTitle(book.title))
                .font(.system(size: BookcaseZoom.titleSize(at: scale), weight: .semibold, design: .serif))
            if let author = book.authors.first, !author.isEmpty, let size = BookcaseZoom.authorSize(at: scale) {
                Text(author)
                    .font(.system(size: size, weight: .medium))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(appearance.textColor.opacity(0.92))
        .lineLimit(1)
        .frame(width: (appearance.spineHeight - 16) * scale, alignment: .leading)
        .rotationEffect(.degrees(-90))
        .frame(width: Self.width(forPageCount: book.pageCount) * scale, height: appearance.spineHeight * scale)
        .overlay(alignment: .topTrailing) {
            if let color = Self.statusColor(status) {
                Circle()
                    .fill(color)
                    .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 6 * max(scale, 0.7), height: 6 * max(scale, 0.7))
                    .padding(.top, 4 * scale)
                    .padding(.trailing, 3 * scale)
            }
        }
        .background(appearance.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(palette.spineOutline, lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    /// Green for Read, blue for Reading, amber for Want; nil (no dot) otherwise.
    static func statusColor(_ status: String?) -> Color? {
        switch status {
        case BookMeta.Status.read: Theme.statusRead
        case BookMeta.Status.reading: Theme.statusReading
        case BookMeta.Status.want: Theme.statusWant
        default: nil
        }
    }

    private var accessibilityText: String {
        var parts = [book.title]
        if let author = book.authors.first, !author.isEmpty { parts.append("by \(author)") }
        if let status, Self.statusColor(status) != nil { parts.append(LibraryFilter.statusTitle(status)) }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    HStack(alignment: .bottom, spacing: 2) {
        ForEach(Book.mocks) { SpineView(book: $0) }
    }
    .padding()
    .background(Theme.wood)
}
