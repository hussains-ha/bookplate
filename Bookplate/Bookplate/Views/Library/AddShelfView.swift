import SwiftUI

struct AddShelfView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var problem: LibraryStore.ShelfNameProblem? { store.shelfNameProblem(name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Shelf name", text: $name)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .onChange(of: name) { _, newValue in
                            if newValue.count > LibraryStore.maxShelfNameLength {
                                name = String(newValue.prefix(LibraryStore.maxShelfNameLength))
                            }
                        }
                } footer: {
                    // A blank name just disables Add; the other problems need explaining.
                    if let problem, problem != .blank {
                        Text(problem.message).foregroundStyle(.red)
                    } else {
                        Text("\(name.count)/\(LibraryStore.maxShelfNameLength)")
                    }
                }
            }
            .navigationTitle("New Shelf")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add).disabled(problem != nil)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.height(220), .medium])
        .presentationBackground(Theme.background)
    }

    private func add() {
        guard store.addShelf(named: name) != nil else { return }
        dismiss()
    }
}

#Preview {
    AddShelfView()
        .environment(LibraryStore.sample())
}
