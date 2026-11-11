import SwiftUI

/// Switch between libraries, and create, rename or delete your own.
struct LibrariesView: View {
    @Environment(LibrarySession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var naming: Naming?
    @State private var name = ""
    @State private var libraryToDelete: LibraryInfo?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var libraryToShare: LibraryInfo?
    @State private var libraryToLeave: LibraryInfo?

    /// The name prompt: a new library, or renaming one.
    private enum Naming: Identifiable {
        case new
        case rename(LibraryInfo)
        var id: String {
            switch self {
            case .new: "new"
            case .rename(let library): library.id.uuidString
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Your libraries") {
                    ForEach(session.owned) { library in
                        row(library)
                            .contextMenu { ownedActions(library) }
                            .swipeActions { ownedActions(library) }
                    }
                    Button {
                        name = ""
                        naming = .new
                    } label: {
                        Label("New Library", systemImage: "plus")
                    }
                    .disabled(isWorking)
                }
                if !session.shared.isEmpty {
                    Section("Shared with you") {
                        ForEach(session.shared) { library in
                            row(library)
                                .contextMenu { leaveAction(library) }
                                .swipeActions(allowsFullSwipe: false) { leaveAction(library) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            // Picks up libraries shared with you (or renamed) since the app started.
            .task { try? await session.refresh() }
            .navigationTitle("Libraries")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Library name", text: $name)
                Button(namingAction) { submitName() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Up to \(LibraryInfo.maxNameLength) characters.")
            }
            .alert(deleteTitle, isPresented: Binding(get: { libraryToDelete != nil },
                                                     set: { if !$0 { libraryToDelete = nil } }),
                   presenting: libraryToDelete) { library in
                Button("Delete", role: .destructive) { delete(library) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its books, shelves and lists are deleted too. This can't be undone.")
            }
            .alert("Leave \u{201C}\(libraryToLeave?.name ?? "")\u{201D}?",
                   isPresented: Binding(get: { libraryToLeave != nil }, set: { if !$0 { libraryToLeave = nil } }),
                   presenting: libraryToLeave) { library in
                Button("Leave", role: .destructive) { leave(library) }
                Button("Cancel", role: .cancel) {}
            } message: { library in
                Text("You'll need \(library.ownerName ?? "the owner") to share it again to see it.")
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil },
                                                         set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(Theme.brown)
        .presentationDetents([.medium, .large])
        .sheet(item: $libraryToShare) { ShareLibraryView(library: $0) }
    }

    private func row(_ library: LibraryInfo) -> some View {
        Button {
            session.select(library.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: library.isOwned ? "books.vertical" : "person.2")
                    .foregroundStyle(Theme.mutedText)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.name)
                        .foregroundStyle(Theme.brown)
                    if let detail = Self.detail(library) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Theme.mutedText)
                    }
                }
                Spacer()
                if library.id == session.currentId {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.brown)
                        .accessibilityLabel("Open")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Shared by Maya · View only" for a friend's library.
    static func detail(_ library: LibraryInfo) -> String? {
        guard !library.isOwned else { return nil }
        let owner = library.ownerName.map { "Shared by \($0)" } ?? "Shared with you"
        return "\(owner) · \(library.canEdit ? "Can edit" : "View only")"
    }

    @ViewBuilder private func ownedActions(_ library: LibraryInfo) -> some View {
        Button("Share…", systemImage: "person.crop.circle.badge.plus") { libraryToShare = library }
            .tint(Theme.brown)
        Button("Rename", systemImage: "pencil") {
            name = library.name
            naming = .rename(library)
        }
        if session.canDelete(library.id) {
            Button("Delete", systemImage: "trash", role: .destructive) { libraryToDelete = library }
        }
    }

    private func leaveAction(_ library: LibraryInfo) -> some View {
        Button("Leave", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
            libraryToLeave = library
        }
        .disabled(isWorking)
    }

    private func leave(_ library: LibraryInfo) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do { try await session.leave(library.id) } catch { errorMessage = error.localizedDescription }
        }
    }

    private var namingTitle: String {
        if case .rename = naming { return "Rename Library" }
        return "New Library"
    }

    private var namingAction: String {
        if case .rename = naming { return "Rename" }
        return "Create"
    }

    private var deleteTitle: String {
        libraryToDelete.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "Delete library?"
    }

    private func submitName() {
        guard let naming else { return }
        let excluding: UUID? = if case .rename(let library) = naming { library.id } else { nil }
        if let problem = session.nameProblem(name, excluding: excluding) {
            errorMessage = problem.message
            return
        }
        let name = name
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                switch naming {
                case .new:
                    _ = try await session.create(named: name)
                    dismiss()
                case .rename(let library):
                    try await session.rename(library.id, to: name)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ library: LibraryInfo) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await session.delete(library.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    let me = UUID()
    let session = LibrarySession(userId: me, ownerName: "Sam", directory: InMemoryLibraryDirectory(userId: me, libraries: [
        LibraryInfo(id: UUID(), name: "Home", ownerId: me, ownerName: "Sam", position: 0, access: .owner),
        LibraryInfo(id: UUID(), name: "Office", ownerId: me, ownerName: "Sam", position: 1, access: .owner),
    ]))
    LibrariesView()
        .environment(session)
        .task { try? await session.start() }
}
