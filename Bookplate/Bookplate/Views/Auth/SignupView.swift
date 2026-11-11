import SwiftUI

struct SignupView: View {
    var onSwitchToLogin: () -> Void

    @Environment(AuthService.self) private var auth

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var error: AuthFailure?
    @State private var isWorking = false

    private func signUp() async {
        error = nil
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
        AuthScreen {
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
                // After the confirmation notice, resending needs a change first (avoids the email rate limit).
                .disabled(isWorking || error == .confirmationRequired)
            }
            .padding(.top, 24)
        } footer: {
            HStack(spacing: 4) {
                Text("Already have an account?").foregroundStyle(Theme.mutedText)
                Button("Sign in", action: onSwitchToLogin)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.brown)
            }
            .font(.footnote)
        }
        .onChange(of: [name, email, password, confirmPassword]) {
            if error == .confirmationRequired { error = nil }
        }
    }
}

#Preview {
    SignupView(onSwitchToLogin: {})
        .environment(AuthService(backend: PreviewAuthBackend()))
}
