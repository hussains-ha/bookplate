import SwiftUI

/// The main app shell.
struct MainTabView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            ListsView()
                .tabItem { Label("Lists", systemImage: "list.bullet") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.brown)
        .overlay(alignment: .top) { SyncBanner() }
    }
}

/// Shows when a change couldn't be saved.
private struct SyncBanner: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Group {
            switch store.syncStatus {
            case .retrying:
                banner("Couldn't save your changes. Retrying…", action: "Retry", perform: store.retrySync)
            case .rejected(let message):
                banner(message, action: "Dismiss", perform: store.dismissSyncRejection)
            case .idle, .saving:
                EmptyView()
            }
        }
        .animation(.default, value: store.syncStatus)
    }

    private func banner(_ text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.icloud")
            Text(text)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action, action: perform)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.brown, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    MainTabView()
        .environment(LibraryStore.sample())
        .environment(AuthService(backend: PreviewAuthBackend()))
}
