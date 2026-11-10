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
        .onChange(of: store.undoStack.last?.id) { _, _ in
            // After an undo, the next older deletion is offered only if it just happened too;
            // an old one coming back would be a surprise (and easy to undo by a reflex tap).
            guard let last = store.undoStack.last else { return shownId = nil }
            shownId = Date().timeIntervalSince(last.date) < Self.duration.seconds ? last.id : nil
        }
        .task(id: shownId) {
            guard shownId != nil else { return }
            try? await Task.sleep(for: Self.duration)
            if !Task.isCancelled { shownId = nil }
        }
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

#Preview {
    UndoToast()
        .environment(LibraryStore.sample())
}
