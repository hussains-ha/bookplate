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
