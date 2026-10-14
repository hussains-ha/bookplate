import SwiftUI

/// Placeholder until the bookshelf UI is built.
struct LibraryView: View {
    var body: some View {
        Text("Library")
            .font(Theme.title(28))
            .foregroundStyle(Theme.brown)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
    }
}

#Preview {
    LibraryView()
}
