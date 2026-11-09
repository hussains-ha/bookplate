import SwiftUI

struct SignupView: View {
    var onSwitchToLogin: () -> Void
    var onBypass: () -> Void

    @Environment(AuthService.self) private var auth

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var error: AuthFailure?
    @State private var isWorking = false

    private func signUp() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.signUp(name: name, email: email, password: password, confirmPassword: confirmPassword)
            error = nil
        } catch {
            self.error = error
        }
    }

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

                if let error {
                    AuthErrorText(error: error)
                }

                Button { Task { await signUp() } } label: {
                    AuthPrimaryLabel(title: "Create account", isWorking: isWorking)
                }
                .disabled(isWorking)
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
        .environment(AuthService(backend: PreviewAuthBackend()))
}
