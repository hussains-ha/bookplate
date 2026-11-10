import SwiftUI

/// Library export, account details and sign-out.
struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LibraryStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ShareLink(item: store.csvExport, preview: SharePreview("Bookplate Library.csv")) {
                        Label("Export spreadsheet", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.books.isEmpty)
                } header: {
                    Text("Library")
                } footer: {
                    Text("A CSV file with each book's shelf, status, dates, rating, notes and tags.")
                }
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
        .environment(LibraryStore.sample())
        .environment(AuthService(backend: PreviewAuthBackend(
            account: AuthUser(id: UUID(), email: "reader@example.com", name: "Abigail"))))
}
