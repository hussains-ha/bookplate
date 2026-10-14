import SwiftUI

struct SignupView: View {
    var onSwitchToLogin: () -> Void
    var onBypass: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            AuthHeader(subtitle: "Create your library.")

            VStack(spacing: 12) {
                AuthTextField(placeholder: "Name", text: $name)
                    .textContentType(.name)

                AuthTextField(placeholder: "Email", text: $email)
                    .textContentType(.emailAddress)
                    .emailFieldStyle()

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .authFieldStyle()

                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .authFieldStyle()

                Button {} label: { AuthPrimaryLabel(title: "Create account") }
            }
            .padding(.top, 24)

            Spacer()

            Button("Skip to library (dev)", action: onBypass)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.brown)
                .accessibilityIdentifier("bypassButton")

            HStack(spacing: 4) {
                Text("Already have an account?").foregroundStyle(Theme.mutedText)
                Button("Sign in", action: onSwitchToLogin)
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
    SignupView(onSwitchToLogin: {}, onBypass: {})
}
