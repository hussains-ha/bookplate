import Foundation

/// How the owner's bookplate and shelf labels look. Saved with the library's settings.
struct BookplateDesign: Codable, Equatable, Sendable {
    enum Style: String, Codable, CaseIterable, Sendable {
        case classic, formal, modern, script, stamp, minimal

        var title: String { rawValue.capitalized }

        /// The phrase shown when the owner hasn't written their own.
        var defaultPhrase: String {
            switch self {
            case .classic: "From the library of"
            case .formal: "Ex Libris"
            case .modern: "Library of"
            case .script: "From the books of"
            case .stamp: "Property of"
            case .minimal: "Books of"
            }
        }
    }

    enum Size: String, Codable, CaseIterable, Sendable {
        case small, medium, large

        var title: String { rawValue.capitalized }

        var scale: Double {
            switch self {
            case .small: 0.85
            case .medium: 1
            case .large: 1.2
            }
        }
    }

    /// Fonts for the shelf name plates.
    enum LabelFont: String, Codable, CaseIterable, Sendable {
        case sans, serif, rounded, mono, typewriter, didot

        var title: String {
            switch self {
            case .sans: "Sans"
            case .serif: "Serif"
            case .rounded: "Rounded"
            case .mono: "Mono"
            case .typewriter: "Typewriter"
            case .didot: "Didot"
            }
        }
    }

    static let labelSizes = 9...14
    static let maxPhraseLength = 40

    var style: Style = .classic
    var size: Size = .medium
    /// The owner's own phrase; blank uses the style's default.
    var phrase: String = ""
    var labelFont: LabelFont = .sans
    /// Shelf label size in points, within `labelSizes`.
    var labelSize: Int = 9

    /// What the plate says above the name.
    var displayPhrase: String {
        let custom = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? style.defaultPhrase : custom
    }

    init(style: Style = .classic, size: Size = .medium, phrase: String = "", labelFont: LabelFont = .sans,
         labelSize: Int = 9) {
        self.style = style
        self.size = size
        self.phrase = phrase
        self.labelFont = labelFont
        self.labelSize = labelSize
    }

    /// Keeps the phrase and label size within their limits.
    var cleaned: BookplateDesign {
        var design = self
        design.phrase = String(phrase.prefix(Self.maxPhraseLength))
        design.labelSize = min(max(labelSize, Self.labelSizes.lowerBound), Self.labelSizes.upperBound)
        return design
    }

    enum CodingKeys: String, CodingKey {
        case style, size, phrase
        case labelFont = "label_font"
        case labelSize = "label_size"
    }

    /// Missing or unknown values (an empty column, or one from a newer app) fall back to the defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: RawRepresentable>(_ key: CodingKeys, _ fallback: T) -> T where T.RawValue == String {
            (try? c.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }.flatMap(T.init(rawValue:)) ?? fallback
        }
        style = value(.style, .classic)
        size = value(.size, .medium)
        labelFont = value(.labelFont, .sans)
        phrase = (try? c.decodeIfPresent(String.self, forKey: .phrase)).flatMap { $0 } ?? ""
        labelSize = (try? c.decodeIfPresent(Int.self, forKey: .labelSize)).flatMap { $0 } ?? 9
        self = cleaned
    }
}
