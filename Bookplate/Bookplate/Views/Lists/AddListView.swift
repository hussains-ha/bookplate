import SwiftUI

struct AddListView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var isFocused: Bool

    private var problem: LibraryStore.ListNameProblem? { store.listNameProblem(name) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List name", text: $name)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .onChange(of: name) { _, newValue in
                            if newValue.count > LibraryStore.maxListNameLength {
                                name = String(newValue.prefix(LibraryStore.maxListNameLength))
                            }
                        }
                } footer: {
                    // A blank name just disables Add; the other problems need explaining.
                    if let problem, problem != .blank {
                        Text(problem.message).foregroundStyle(.red)
                    } else {
                        Text("\(name.count)/\(LibraryStore.maxListNameLength)")
                    }
                }
            }
            .navigationTitle("New List")
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
        guard store.addList(named: name) != nil else { return }
        dismiss()
    }
}

#Preview {
    AddListView()
        .environment(LibraryStore.sample())
}
