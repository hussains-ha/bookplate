import SwiftUI

/// Shows the auth screens or the main app, following the auth session.
struct RootView: View {
    @Environment(AuthService.self) private var auth
    @State private var showingSignup = false

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background.ignoresSafeArea())
            case .signedOut:
                if showingSignup {
                    SignupView(onSwitchToLogin: { showingSignup = false })
                } else {
                    LoginView(onSwitchToSignup: { showingSignup = true })
                }
            case .signedIn(let user):
                SignedInLibraryView(user: user)
                    .id(user.id)
            }
        }
        .onChange(of: auth.state) { showingSignup = false }
    }
}

#Preview {
    RootView()
        .environment(AuthService(backend: PreviewAuthBackend()))
}
