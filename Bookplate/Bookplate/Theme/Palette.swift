import SwiftUI

/// The colors of one bookcase appearance. The library screen reads it from the environment.
struct Palette: Equatable {
    /// Screen background behind the bookcase.
    var background: Color
    /// Buttons, titles and other accents on the screen background.
    var accent: Color
    var mutedText: Color
    /// The bookcase frame behind the shelves.
    var frame: Color
    /// The strip under each shelf of books.
    var shelf: Color
    /// Text and icons drawn on the shelf strip (book count, sort menu, empty-shelf note).
    var shelfText: Color
    /// Shelf name plates.
    var plate: Color
    var plateText: Color

    static func of(_ appearance: Bookshelf.Appearance) -> Palette {
        switch appearance {
        case .classic: .classic
        case .maple: .maple
        case .modern: .modern
        }
    }

    /// Dark walnut, from the design mockups.
    static let classic = Palette(
        background: Theme.background, accent: Theme.brown, mutedText: Theme.mutedText,
        frame: Theme.wood, shelf: Theme.woodShelf, shelfText: Theme.label,
        plate: Theme.label, plateText: Theme.brown
    )

    /// Light honey maple.
    static let maple = Palette(
        background: Color(red: 0.96, green: 0.92, blue: 0.85),
        accent: Color(red: 0.47, green: 0.29, blue: 0.13),
        mutedText: Color(red: 0.53, green: 0.43, blue: 0.33),
        frame: Color(red: 0.70, green: 0.50, blue: 0.29),
        shelf: Color(red: 0.84, green: 0.65, blue: 0.42),
        shelfText: Color(red: 0.30, green: 0.18, blue: 0.08),
        plate: Color(red: 0.99, green: 0.96, blue: 0.88),
        plateText: Color(red: 0.36, green: 0.22, blue: 0.10)
    )

    /// Charcoal and white.
    static let modern = Palette(
        background: Color(red: 0.94, green: 0.94, blue: 0.95),
        accent: Color(red: 0.14, green: 0.15, blue: 0.17),
        mutedText: Color(red: 0.42, green: 0.43, blue: 0.47),
        frame: Color(red: 0.18, green: 0.19, blue: 0.21),
        shelf: Color(red: 0.30, green: 0.31, blue: 0.34),
        shelfText: Color(red: 0.93, green: 0.93, blue: 0.95),
        plate: Color(red: 0.97, green: 0.97, blue: 0.98),
        plateText: Color(red: 0.14, green: 0.15, blue: 0.17)
    )
}

extension Bookshelf.Appearance {
    var title: String {
        switch self {
        case .classic: "Classic"
        case .maple: "Maple"
        case .modern: "Modern"
        }
    }
}

extension EnvironmentValues {
    @Entry var palette: Palette = .classic
}
