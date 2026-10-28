import SwiftUI

/// A book's generated look (color and size), shared by its spine and its generated front cover.
struct BookAppearance {
    let color: Color
    let spineHeight: CGFloat

    init(bookId: String) {
        // Deterministic (unlike `hashValue`) so a book keeps its look across launches.
        let seed = bookId.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
        color = Theme.spineColors[seed % Theme.spineColors.count]
        spineHeight = 92 + CGFloat(seed % 5) * 6
    }

    var textColor: Color {
        color == Theme.spineColors[5] ? Theme.brown : .white
    }
}
