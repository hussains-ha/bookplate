import SwiftUI

/// Classic appearance palette from the design mockups.
enum Theme {
    static let background = Color(red: 0.89, green: 0.85, blue: 0.78)
    static let field = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let brown = Color(red: 0.25, green: 0.16, blue: 0.11)
    static let mutedText = Color(red: 0.45, green: 0.38, blue: 0.32)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
}

extension Theme {
    static let wood = Color(red: 0.24, green: 0.15, blue: 0.10)
    static let woodShelf = Color(red: 0.34, green: 0.22, blue: 0.14)
    static let label = Color(red: 0.93, green: 0.88, blue: 0.78)

    static let spineColors: [Color] = [
        Color(red: 0.55, green: 0.15, blue: 0.18), Color(red: 0.13, green: 0.35, blue: 0.30),
        Color(red: 0.16, green: 0.25, blue: 0.48), Color(red: 0.78, green: 0.58, blue: 0.20),
        Color(red: 0.35, green: 0.20, blue: 0.45), Color(red: 0.85, green: 0.82, blue: 0.74),
        Color(red: 0.20, green: 0.20, blue: 0.22), Color(red: 0.72, green: 0.35, blue: 0.20),
    ]
}
