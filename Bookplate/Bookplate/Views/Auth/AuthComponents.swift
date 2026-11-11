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
    var isWorking = false

    var body: some View {
        Group {
            if isWorking {
                ProgressView().tint(.white)
                    .accessibilityLabel("\(title), in progress")
            } else {
                Text(title)
            }
        }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(Theme.brown, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AuthErrorText: View {
    let error: AuthFailure

    var body: some View {
        Text(error.localizedDescription)
            .font(.footnote)
            // Confirmation is a next step, not a failure.
            .foregroundStyle(error == .confirmationRequired ? Theme.brown : .red)
            .multilineTextAlignment(.center)
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
    /// Email keyboard, no autocapitalization or autocorrection; these modifiers are iOS-only.
    @ViewBuilder
    func emailFieldStyle() -> some View {
        #if os(iOS)
        self
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}

/// Lays out an auth screen: content anchored to the top, footer at the bottom of the screen.
/// Nothing above the fields grows or shrinks, so the fields stay put when the keyboard opens
/// (a tap on a field never lands on something that slid into its place).
struct AuthScreen<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    static func endEditing() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    content
                    Spacer(minLength: 24)
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                // Inside the scroll view so it gets the taps: a tap on empty space hides the keyboard.
                // Fields and buttons on top still take their own taps.
                .background(Color.clear.contentShape(Rectangle()).onTapGesture { Self.endEditing() })
            }
            // Always draggable, so a swipe hides the keyboard and uncovers the footer even when everything fits.
            .scrollBounceBehavior(.always)
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}
