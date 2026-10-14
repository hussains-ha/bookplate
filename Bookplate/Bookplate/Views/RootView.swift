import SwiftUI

/// Switches between the auth screens and the main app.
/// Placeholder state until the auth service exists.
struct RootView: View {
    private enum Screen { case login, signup, library }

    @State private var screen: Screen = .login

    var body: some View {
        switch screen {
        case .login:
            LoginView(onSwitchToSignup: { screen = .signup }, onBypass: { screen = .library })
        case .signup:
            SignupView(onSwitchToLogin: { screen = .login }, onBypass: { screen = .library })
        case .library:
            MainTabView()
        }
    }
}

#Preview {
    RootView()
        .environment(LibraryStore.sample())
}
