import SwiftUI

/// "Deleted X · Undo" after a shelf or book is deleted. Hides after a few seconds.
/// Undoing shows the next older deletion, so up to `LibraryStore.maxUndo` can be undone in a row.
struct UndoToast: View {
    @Environment(LibraryStore.self) private var store
    @State private var shownId: UUID?

    static let duration: Duration = .seconds(5)

    private var deletion: LibraryStore.Deletion? {
        guard let last = store.undoStack.last, last.id == shownId else { return nil }
        return last
    }

    var body: some View {
        Group {
            if let deletion {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                    Text("Deleted \u{201C}\(deletion.name)\u{201D}")
                        .font(.footnote)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Undo") {
                        withAnimation(.snappy) { _ = store.undoLastDeletion() }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.brown, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                .padding(.horizontal, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: "Undo") { _ = store.undoLastDeletion() }
            }
        }
        .animation(.snappy, value: deletion?.id)
        .onChange(of: store.undoStack.last?.id) { _, newId in shownId = newId }
        .task(id: shownId) {
            guard shownId != nil else { return }
            try? await Task.sleep(for: Self.duration)
            if !Task.isCancelled { shownId = nil }
        }
    }
}

#Preview {
    UndoToast()
        .environment(LibraryStore.sample())
}
