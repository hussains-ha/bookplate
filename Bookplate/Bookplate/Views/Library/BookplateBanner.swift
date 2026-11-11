import SwiftUI

/// The owner's bookplate: "From the library of <name>".
struct BookplateBanner: View {
    let name: String
    var compact = false

    static let phrase = "From the library of"

    /// The name to show for an account, or nil (no banner) when it has none.
    static func ownerName(_ user: AuthUser?) -> String? {
        guard let name = user?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }

    var body: some View {
        VStack(spacing: compact ? 0 : 2) {
            Text(Self.phrase)
                .font(.system(size: compact ? 9 : 10, weight: .medium, design: .serif).italic())
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Theme.mutedText)
            Text(name)
                .font(Theme.title(compact ? 15 : 19))
                .foregroundStyle(Theme.brown)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, compact ? 14 : 22)
        .padding(.vertical, compact ? 5 : 8)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.brown.opacity(0.55), lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Theme.brown.opacity(0.25), lineWidth: 0.5).padding(3))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 20) {
        BookplateBanner(name: "Sam Reader")
        BookplateBanner(name: "Sam Reader", compact: true)
    }
    .padding()
    .background(Theme.background)
}
