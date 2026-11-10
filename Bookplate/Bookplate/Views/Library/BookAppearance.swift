import SwiftUI

/// A book's generated look (color, size and cover layout), shared by its spine and its generated front cover.
/// Seeded by title + first author, so a book looks the same even after it's deleted and re-added.
struct BookAppearance {
    let color: Color
    let spineHeight: CGFloat
    let coverLayout: CoverLayout

    /// The eight generated front-cover layouts.
    enum CoverLayout: Int, CaseIterable {
        case centered, top, bottom, split, minimal, bold, classic, stripe
    }

    init(book: Book) {
        self.init(title: book.title, author: book.authors.first)
    }

    init(title: String, author: String?) {
        let seed = Self.seed(title: title, author: author)
        color = Theme.spineColors[seed % Theme.spineColors.count]
        spineHeight = 92 + CGFloat((seed / 8) % 5) * 6
        // Different bits from the color, so layout and color vary independently.
        coverLayout = CoverLayout.allCases[(seed / 40) % CoverLayout.allCases.count]
    }

    /// Deterministic (unlike `hashValue`) so a book keeps its look across launches.
    /// Case, spacing and parenthesized subtitles don't change it.
    static func seed(title: String, author: String?) -> Int {
        let key = normalized(displayTitle(title)) + "|" + normalized(author ?? "")
        // FNV-1a, folded to a non-negative Int.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return Int(hash % 1_000_000_007)
    }

    /// The title without parenthesized parts, e.g. "Dune (Dune Chronicles, #1)" → "Dune".
    /// Falls back to the original title if nothing would be left.
    static func displayTitle(_ title: String) -> String {
        let stripped = title
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? title.trimmingCharacters(in: .whitespacesAndNewlines) : stripped
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    var textColor: Color {
        color == Theme.spineColors[5] ? Theme.brown : .white
    }

    /// The fill used by both the spine and the cover: lighter at the top, darker at the bottom.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [color.mix(with: .white, by: 0.12), color, color.mix(with: .black, by: 0.18)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// A contrasting accent for rules, frames and the stripe band.
    var accentColor: Color {
        textColor == .white ? Theme.label : Theme.brown
    }
}
