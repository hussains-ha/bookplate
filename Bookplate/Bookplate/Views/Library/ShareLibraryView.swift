import SwiftUI

/// Share one of your libraries: invite people by email, change their role, remove them, or stop sharing.
struct ShareLibraryView: View {
    let library: LibraryInfo
    @Environment(\.dismiss) private var dismiss
    @State private var model: ShareModel

    @State private var email = ""
    @State private var role = LibraryMember.Role.view
    @State private var problem: String?
    @State private var invitedName: String?
    @State private var isLoading = true
    @State private var showingStopConfirm = false
    @FocusState private var emailFocused: Bool

    init(library: LibraryInfo, sharing: LibrarySharing = SupabaseLibrarySharing()) {
        self.library = library
        _model = State(initialValue: ShareModel(libraryId: library.id, sharing: sharing))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Friend's email", text: $email)
                        .textContentType(.emailAddress)
                        .emailFieldStyle()
                        .focused($emailFocused)
                        .submitLabel(.send)
                        .onSubmit(invite)
                    Picker("Access", selection: $role) {
                        ForEach(LibraryMember.Role.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button(action: invite) {
                        HStack {
                            Text("Invite")
                            if model.isWorking { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
                } header: {
                    Text("Invite a friend")
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(.red)
                    } else if let invitedName {
                        Text("\(invitedName) can now open \u{201C}\(library.name)\u{201D} from their Libraries.")
                    } else {
                        Text("They need a Bookplate account. Can view lets them look; Can edit lets them change books, shelves and lists.")
                    }
                }

                Section("People with access") {
                    LabeledContent {
                        Text("Owner").foregroundStyle(Theme.mutedText)
                    } label: {
                        Text("You")
                    }
                    if isLoading {
                        ProgressView()
                    }
                    ForEach(model.members) { member in
                        memberRow(member)
                    }
                }

                if !model.members.isEmpty {
                    Section {
                        Button("Stop Sharing", role: .destructive) { showingStopConfirm = true }
                    } footer: {
                        Text("Removes everyone's access to this library.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Share \u{201C}\(library.name)\u{201D}")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Stop sharing \u{201C}\(library.name)\u{201D}?", isPresented: $showingStopConfirm) {
                Button("Stop Sharing", role: .destructive) { perform { () async throws(BookServiceError) in try await model.stopSharing() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Nobody else will be able to open it.")
            }
            .task {
                do { try await model.load() } catch { problem = error.localizedDescription }
                isLoading = false
            }
            .onChange(of: email) {
                // Typing a new address clears the last result (clearing the field after an invite doesn't).
                guard !email.isEmpty else { return }
                problem = nil
                invitedName = nil
            }
        }
        .tint(Theme.brown)
    }

    private func memberRow(_ member: LibraryMember) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName).foregroundStyle(Theme.brown)
                if member.name != nil {
                    Text(member.email).font(.caption).foregroundStyle(Theme.mutedText)
                }
            }
            Spacer()
            Menu {
                ForEach(LibraryMember.Role.allCases, id: \.self) { role in
                    Button {
                        perform { () async throws(BookServiceError) in try await model.setRole(role, for: member) }
                    } label: {
                        if member.role == role { Label(role.title, systemImage: "checkmark") } else { Text(role.title) }
                    }
                }
                Divider()
                Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                    perform { () async throws(BookServiceError) in try await model.remove(member) }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(member.role.title)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.subheadline)
            }
            .accessibilityLabel("\(member.displayName), \(member.role.title)")
        }
    }

    private func invite() {
        let email = email, role = role
        problem = nil
        Task {
            do throws(ShareProblem) {
                try await model.invite(email: email, role: role)
                let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
                invitedName = model.members.first { $0.email.caseInsensitiveCompare(trimmed) == .orderedSame }?.displayName ?? trimmed
                self.email = ""
            } catch {
                problem = error.message
            }
        }
    }

    private func perform(_ action: @escaping () async throws(BookServiceError) -> Void) {
        // A new change replaces the last message, so an old error doesn't linger under the invite field.
        problem = nil
        invitedName = nil
        Task {
            do { try await action() } catch { problem = error.localizedDescription }
        }
    }
}

#Preview {
    ShareLibraryView(
        library: LibraryInfo(id: UUID(), name: "Home", ownerId: UUID(), ownerName: "Sam", position: 0, access: .owner),
        sharing: InMemoryLibrarySharing(accounts: ["maya@example.com": (UUID(), "Maya")])
    )
}
