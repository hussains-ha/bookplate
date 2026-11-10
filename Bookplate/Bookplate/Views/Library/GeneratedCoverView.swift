import SwiftUI

/// A front cover drawn from a book's title and first author, in one of eight layouts.
/// Shares its color, gradient and serif font with the book's spine so the two match.
struct GeneratedCoverView: View {
    let book: Book
    /// Overrides the book's own layout (previews only).
    var layout: BookAppearance.CoverLayout?

    private var appearance: BookAppearance { BookAppearance(book: book) }
    private var title: String { BookAppearance.displayTitle(book.title) }
    private var author: String? {
        guard let author = book.authors.first?.trimmingCharacters(in: .whitespaces), !author.isEmpty else { return nil }
        return author
    }

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    // Fonts and spacing are designed for a 120pt-wide cover and scale with it.
                    let unit = proxy.size.width / 120
                    content(unit: unit)
                        .foregroundStyle(appearance.textColor)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(appearance.gradient)
                        .overlay { depth(unit: unit) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            // The drop shadow lives on a shape behind the book, so the text doesn't get one.
            .background {
                RoundedRectangle(cornerRadius: 3)
                    .fill(appearance.color)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 2, y: 3)
            }
            .accessibilityElement()
            .accessibilityLabel(author.map { "\(title) by \($0)" } ?? title)
    }

    // MARK: Layouts

    @ViewBuilder
    private func content(unit: CGFloat) -> some View {
        let inset = 12 * unit
        switch layout ?? appearance.coverLayout {
        case .centered:
            VStack(spacing: 8 * unit) {
                titleText(size: 17, unit: unit)
                authorText(size: 9, unit: unit)
            }
            .multilineTextAlignment(.center)
            .padding(inset)

        case .top:
            VStack(alignment: .leading, spacing: 5 * unit) {
                authorText(size: 8, unit: unit, uppercase: true)
                titleText(size: 17, unit: unit)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(inset)
            .padding(.leading, 4 * unit)

        case .bottom:
            VStack(alignment: .leading, spacing: 5 * unit) {
                Spacer(minLength: 0)
                titleText(size: 17, unit: unit)
                authorText(size: 9, unit: unit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(inset)
            .padding(.leading, 4 * unit)

        case .split:
            VStack(spacing: 0) {
                titleText(size: 16, unit: unit)
                Spacer(minLength: 8 * unit)
                rule(unit: unit).frame(width: 30 * unit)
                authorText(size: 8, unit: unit, uppercase: true)
                    .padding(.top, 6 * unit)
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, 16 * unit)
            .padding(.horizontal, inset)

        case .minimal:
            VStack(spacing: 4 * unit) {
                Spacer(minLength: 0)
                titleText(size: 12, unit: unit, weight: .medium)
                authorText(size: 7, unit: unit)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 22 * unit)
            .padding(.horizontal, 18 * unit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Rectangle()
                    .stroke(appearance.accentColor.opacity(0.5), lineWidth: 0.75 * unit)
                    .padding(9 * unit)
            }

        case .bold:
            VStack(alignment: .leading, spacing: 0) {
                titleText(size: 24, unit: unit, weight: .black, uppercase: true)
                    .lineLimit(5)
                Spacer(minLength: 6 * unit)
                authorText(size: 9, unit: unit, uppercase: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(inset)
            .padding(.leading, 2 * unit)

        case .classic:
            VStack(spacing: 7 * unit) {
                titleText(size: 15, unit: unit)
                HStack(spacing: 4 * unit) {
                    rule(unit: unit).frame(width: 14 * unit)
                    Image(systemName: "diamond.fill").font(.system(size: 4 * unit))
                    rule(unit: unit).frame(width: 14 * unit)
                }
                .foregroundStyle(appearance.accentColor)
                authorText(size: 8, unit: unit)
            }
            .multilineTextAlignment(.center)
            .padding(22 * unit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                ZStack {
                    Rectangle().stroke(appearance.accentColor.opacity(0.75), lineWidth: 1 * unit)
                        .padding(9 * unit)
                    Rectangle().stroke(appearance.accentColor.opacity(0.5), lineWidth: 0.5 * unit)
                        .padding(12 * unit)
                }
            }

        case .stripe:
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Spacer().frame(height: proxy.size.height * 0.3)
                    titleText(size: 15, unit: unit)
                        .foregroundStyle(appearance.color)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, inset)
                        .padding(.vertical, 10 * unit)
                        .frame(maxWidth: .infinity)
                        .background(appearance.accentColor)
                    authorText(size: 8, unit: unit, uppercase: true)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10 * unit)
                        .padding(.horizontal, inset)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func titleText(size: CGFloat, unit: CGFloat, weight: Font.Weight = .bold, uppercase: Bool = false) -> some View {
        Text(uppercase ? title.uppercased() : title)
            .font(.system(size: size * unit, weight: weight, design: .serif))
            .lineLimit(4)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func authorText(size: CGFloat, unit: CGFloat, uppercase: Bool = false) -> some View {
        if let author {
            Text(uppercase ? author.uppercased() : author)
                .font(.system(size: size * unit, weight: uppercase ? .semibold : .regular, design: .serif))
                .tracking(uppercase ? 1 * unit : 0)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .opacity(0.85)
        }
    }

    private func rule(unit: CGFloat) -> some View {
        Rectangle()
            .fill(appearance.accentColor.opacity(0.8))
            .frame(height: 0.75 * unit)
    }

    // MARK: Depth

    /// Binding shadow on the left edge and a thin page-edge highlight on the right.
    private func depth(unit: CGFloat) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.08), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 9 * unit)
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 0.75 * unit)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .white.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 2.5 * unit)
        }
        .allowsHitTesting(false)
    }
}

#Preview("All layouts") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], spacing: 20) {
            ForEach(BookAppearance.CoverLayout.allCases, id: \.self) { layout in
                VStack {
                    GeneratedCoverView(
                        book: Book(id: "p-\(layout)", title: "The Left Hand of Darkness (Hainish Cycle #4)",
                                   authors: ["Ursula K. Le Guin"], pageCount: nil, coverUrl: nil, isbn13: nil),
                        layout: layout
                    )
                    Text(String(describing: layout)).font(.caption)
                }
            }
        }
        .padding()
    }
    .background(Theme.background)
}
