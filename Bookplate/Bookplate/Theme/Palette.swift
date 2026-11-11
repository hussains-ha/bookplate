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
    /// The search field on the library screen.
    var field: Color
    var fieldBorder: Color
    /// A hairline around each spine, so spines close in color to the shelf still stand out.
    var spineOutline: Color

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
        plate: Theme.label, plateText: Theme.brown,
        field: Theme.field, fieldBorder: Theme.brown.opacity(0.15),
        spineOutline: Color.white.opacity(0.12)
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
        plateText: Color(red: 0.36, green: 0.22, blue: 0.10),
        field: Color(red: 1.00, green: 0.98, blue: 0.94),
        fieldBorder: Color(red: 0.47, green: 0.29, blue: 0.13).opacity(0.22),
        spineOutline: Color(red: 0.25, green: 0.14, blue: 0.05).opacity(0.75)
    )

    /// Slate, charcoal and white.
    static let modern = Palette(
        background: Color(red: 0.94, green: 0.94, blue: 0.95),
        accent: Color(red: 0.14, green: 0.15, blue: 0.17),
        mutedText: Color(red: 0.42, green: 0.43, blue: 0.47),
        // A mid slate case under charcoal ledges, so both dark and light spines stand out.
        frame: Color(red: 0.45, green: 0.47, blue: 0.51),
        shelf: Color(red: 0.24, green: 0.25, blue: 0.28),
        shelfText: Color(red: 0.93, green: 0.93, blue: 0.95),
        plate: Color(red: 0.97, green: 0.97, blue: 0.98),
        plateText: Color(red: 0.14, green: 0.15, blue: 0.17),
        field: Color.white,
        fieldBorder: Color(red: 0.14, green: 0.15, blue: 0.17).opacity(0.14),
        spineOutline: Color.white.opacity(0.35)
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
