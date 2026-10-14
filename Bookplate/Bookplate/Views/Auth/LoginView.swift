import SwiftUI

struct LoginView: View {
    var onSwitchToSignup: () -> Void
    var onSignIn: () -> Void
    var onBypass: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showError = false

    /// Placeholder credentials until the auth service exists.
    private func signIn() {
        if email == "devuser" && password == "pass" {
            showError = false
            onSignIn()
        } else {
            showError = true
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            AuthHeader(subtitle: "Your library, on real shelves.")

            VStack(spacing: 12) {
                Button {} label: {
                    Label("Continue with Apple", systemImage: "apple.logo")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(.black, in: RoundedRectangle(cornerRadius: 10))
                }

                Text("or use email")
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)

                AuthTextField(placeholder: "Email", text: $email)
                    .textContentType(.emailAddress)
                    .emailFieldStyle()

                HStack {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(.password)
                    Button(showPassword ? "Hide" : "Show") { showPassword.toggle() }
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedText)
                }
                .authFieldStyle()

                if showError {
                    Text("Incorrect email or password.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button(action: signIn) { AuthPrimaryLabel(title: "Sign in") }

                Button("Forgot password?") {}
                    .font(.footnote)
                    .foregroundStyle(Theme.brown)
            }
            .padding(.top, 24)

            Spacer()

            Button("Skip to library (dev)", action: onBypass)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.brown)
                .accessibilityIdentifier("bypassButton")

            HStack(spacing: 4) {
                Text("New to Bookplate?").foregroundStyle(Theme.mutedText)
                Button("Create account", action: onSwitchToSignup)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.brown)
            }
            .font(.footnote)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}

#Preview {
    LoginView(onSwitchToSignup: {}, onSignIn: {}, onBypass: {})
}
