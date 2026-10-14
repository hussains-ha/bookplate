import SwiftUI

/// The main app shell. Only Library is built so far.
struct MainTabView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            PlaceholderTab(title: "Lists")
                .tabItem { Label("Lists", systemImage: "list.bullet") }
            PlaceholderTab(title: "Stats")
                .tabItem { Label("Stats", systemImage: "chart.bar") }
            PlaceholderTab(title: "Settings")
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.brown)
    }
}

private struct PlaceholderTab: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.title(28))
            .foregroundStyle(Theme.brown)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
    }
}

#Preview {
    MainTabView()
        .environment(LibraryStore.sample())
}
