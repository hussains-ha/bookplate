import SwiftUI

/// The owner's bookplate: a phrase ("From the library of") and their name, in one of six styles.
struct BookplateBanner: View {
    let name: String
    var design = BookplateDesign()
    var compact = false

    /// The plate's name for a library: the owner's for a library shared with you, otherwise yours.
    static func ownerName(_ user: AuthUser?, library: LibraryInfo?) -> String? {
        if let library, !library.isOwned {
            guard let name = library.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            return name
        }
        return ownerName(user)
    }

    /// The name to show for an account, or nil (no banner) when it has none.
    static func ownerName(_ user: AuthUser?) -> String? {
        guard let name = user?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    private static let gold = Color(red: 0.86, green: 0.70, blue: 0.38)
    private static let stampRed = Color(red: 0.66, green: 0.16, blue: 0.14)

    private var scale: Double { (compact ? 0.8 : 1) * design.size.scale }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch design.style {
        case .classic:
            plate(phraseFont: .system(size: 10 * scale, weight: .medium, design: .serif).italic(), uppercase: true,
                  nameFont: Theme.title(19 * scale), ink: Theme.brown, muted: Theme.mutedText)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.brown.opacity(0.55), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.brown.opacity(0.25), lineWidth: 0.5).padding(3))
        case .formal:
            plate(phraseFont: .system(size: 10 * scale, weight: .semibold, design: .serif), uppercase: true,
                  nameFont: .system(size: 20 * scale, weight: .regular, design: .serif), ink: Self.gold,
                  muted: Self.gold.opacity(0.8))
                .background(Theme.brown, in: RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 1).stroke(Self.gold.opacity(0.8), lineWidth: 1).padding(4))
        case .modern:
            HStack(spacing: 10 * scale) {
                Rectangle().fill(Theme.brown).frame(width: 3 * scale)
                VStack(alignment: .leading, spacing: 1) {
                    Text(design.displayPhrase)
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(Theme.mutedText)
                    nameText(.system(size: 19 * scale, weight: .bold), Theme.brown)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6 * scale)
            .padding(.trailing, 14 * scale)
            .background(Theme.field, in: Rectangle())
        case .script:
            plate(phraseFont: .system(size: 12 * scale, design: .serif).italic(), uppercase: false,
                  nameFont: .custom("SnellRoundhand-Bold", size: 26 * scale, relativeTo: .title), ink: Theme.brown,
                  muted: Theme.mutedText)
                .background(Theme.field, in: Capsule())
                .overlay(Capsule().stroke(Theme.brown.opacity(0.4), lineWidth: 1))
        case .stamp:
            plate(phraseFont: .system(size: 10 * scale, weight: .bold, design: .monospaced), uppercase: true,
                  nameFont: .system(size: 18 * scale, weight: .heavy, design: .monospaced), ink: Self.stampRed,
                  muted: Self.stampRed.opacity(0.85), uppercaseName: true)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .stroke(Self.stampRed, style: StrokeStyle(lineWidth: 2, dash: [5, 2])))
                .rotationEffect(.degrees(-2))
        case .minimal:
            plate(phraseFont: .system(size: 11 * scale), uppercase: false,
                  nameFont: .system(size: 18 * scale, weight: .semibold), ink: Theme.brown, muted: Theme.mutedText)
        }
    }

    private func plate(phraseFont: Font, uppercase: Bool, nameFont: Font, ink: Color, muted: Color,
                       uppercaseName: Bool = false) -> some View {
        VStack(spacing: 2 * scale) {
            Text(design.displayPhrase)
                .font(phraseFont)
                .textCase(uppercase ? .uppercase : nil)
                .tracking(uppercase ? 1.2 : 0)
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            nameText(nameFont, ink)
                .textCase(uppercaseName ? .uppercase : nil)
        }
        .padding(.horizontal, 22 * scale)
        .padding(.vertical, 8 * scale)
    }

    private func nameText(_ font: Font, _ ink: Color) -> some View {
        Text(name)
            .font(font)
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

extension BookplateDesign {
    /// The font for shelf name plates; `scale` follows the bookcase zoom.
    func shelfLabelFont(scale: Double = 1, sizeOffset: Double = 0) -> Font {
        let size = (Double(labelSize) + sizeOffset) * scale
        return switch labelFont {
        case .sans: .system(size: size, weight: .bold)
        case .serif: .system(size: size, weight: .bold, design: .serif)
        case .rounded: .system(size: size, weight: .bold, design: .rounded)
        case .mono: .system(size: size, weight: .bold, design: .monospaced)
        case .typewriter: .custom("AmericanTypewriter-Bold", fixedSize: size)
        case .didot: .custom("Didot-Bold", fixedSize: size)
        }
    }
}

extension EnvironmentValues {
    @Entry var bookplateDesign = BookplateDesign()
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            ForEach(BookplateDesign.Style.allCases, id: \.self) { style in
                BookplateBanner(name: "Sam Reader", design: BookplateDesign(style: style))
            }
        }
        .padding()
    }
    .background(Theme.background)
}
