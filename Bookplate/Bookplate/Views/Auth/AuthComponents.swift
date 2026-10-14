import SwiftUI

/// Logo and wordmark shared by the login and signup screens.
struct AuthHeader: View {
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brown)
                .frame(width: 88, height: 88)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.brown.opacity(0.4)))
            Text("Bookplate")
                .font(Theme.title(34))
                .foregroundStyle(Theme.brown)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.mutedText)
        }
    }
}

struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .authFieldStyle()
    }
}

struct AuthPrimaryLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(Theme.brown, in: RoundedRectangle(cornerRadius: 10))
    }
}

extension View {
    func authFieldStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.brown.opacity(0.15)))
    }
}

extension View {
    /// Email keyboard and no autocapitalization; these modifiers are iOS-only.
    @ViewBuilder
    func emailFieldStyle() -> some View {
        #if os(iOS)
        self
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
