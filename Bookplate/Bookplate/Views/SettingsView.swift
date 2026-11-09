import SwiftUI

/// Account details and sign-out. The rest of Settings comes later.
struct SettingsView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let user = auth.user {
                        if let name = user.name {
                            LabeledContent("Name", value: name)
                        }
                        LabeledContent("Email", value: user.email ?? "—")
                    } else {
                        Text("Not signed in (dev skip)")
                            .foregroundStyle(Theme.mutedText)
                    }
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthService(backend: PreviewAuthBackend(
            account: AuthUser(id: UUID(), email: "reader@example.com", name: "Abigail"))))
}
