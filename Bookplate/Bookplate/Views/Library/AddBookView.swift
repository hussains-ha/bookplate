import SwiftUI

struct AddBookView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var author = ""
    @State private var pages = ""
    @State private var shelfId: String
    @State private var duplicate: Book?
    @State private var checkedDeviceOnly = false
    @State private var isChecking = false

    init(defaultShelfId: String?) {
        _shelfId = State(initialValue: defaultShelfId ?? "")
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pageCount: Int? { Int(pages.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil } }
    private var canAdd: Bool { !trimmedTitle.isEmpty && !store.allShelvesLocked }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Pages (optional)", text: $pages)
                        .numberKeyboard()
                }
                if store.allShelvesLocked {
                    Section {
                        Text("All your shelves are locked. Unlock a shelf to add a book.")
                            .foregroundStyle(.secondary)
                    }
                } else if !store.bookshelf.shelves.isEmpty {
                    Section {
                        Picker("Shelf", selection: $shelfId) {
                            ForEach(store.bookshelf.shelves.filter { !$0.isLocked }) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isChecking {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await attemptAdd() } }.disabled(!canAdd)
                    }
                }
            }
            .alert("Possible duplicate", isPresented: Binding(
                get: { duplicate != nil },
                set: { if !$0 { duplicate = nil } }
            )) {
                Button("Cancel", role: .cancel) {}
                Button("Add Anyway") { add() }
            } message: {
                if let duplicate {
                    Text("\"\(duplicate.title)\" is already in your library. Add it again?"
                         + (checkedDeviceOnly ? "\n\nYou're offline, so only the books on this device were checked." : ""))
                }
            }
        }
    }

    private func attemptAdd() async {
        isChecking = true
        let check = await store.checkDuplicate(title: trimmedTitle, author: author)
        isChecking = false
        checkedDeviceOnly = check.checkedDeviceOnly
        if let existing = check.match {
            duplicate = existing
        } else {
            add()
        }
    }

    private func add() {
        store.addBook(title: trimmedTitle, author: author, pageCount: pageCount, shelfId: shelfId)
        dismiss()
    }
}

private extension View {
    @ViewBuilder
    func numberKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
    }
}

#Preview {
    AddBookView(defaultShelfId: Shelf.mock.id)
        .environment(LibraryStore.sample())
}
