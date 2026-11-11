import SwiftUI

/// Library export, account details and sign-out.
struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(LibraryStore.self) private var store
    @State private var showingDesigner = false

    var body: some View {
        NavigationStack {
            List {
                // First, so Sign out is never under the floating tab bar.
                Section("Account") {
                    if let name = auth.user?.name {
                        LabeledContent("Name", value: name)
                    }
                    LabeledContent("Email", value: auth.user?.email ?? "—")
                    Button("Sign out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                }
                Section("Appearance") {
                    Picker("Bookcase", selection: Binding(get: { store.bookshelf.appearance },
                                                          set: { store.setAppearance($0) })) {
                        ForEach(Bookshelf.Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Bookcase appearance")
                    .listRowSeparator(.hidden)
                    BookcaseSwatch(palette: .of(store.bookshelf.appearance), labelFont: store.settings.bookplate.shelfLabelFont())
                    Button { showingDesigner = true } label: {
                        LabeledContent("Bookplate", value: store.settings.bookplate.style.title)
                    }
                    .foregroundStyle(Theme.brown)
                }
                Section {
                    let export = store.csvExport
                    ShareLink(item: export, preview: SharePreview(export.fileName)) {
                        Label("Export spreadsheet", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.books.isEmpty)
                } header: {
                    Text("Library")
                } footer: {
                    Text("A CSV file with each book's shelf, status, dates, rating, notes and tags.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .sheet(isPresented: $showingDesigner) {
                BookplateDesignerView(name: BookplateBanner.ownerName(auth.user), design: store.settings.bookplate)
                    .environment(\.palette, .of(store.bookshelf.appearance))
            }
        }
    }
}

/// A small picture of the bookcase in the chosen appearance.
private struct BookcaseSwatch: View {
    let palette: Palette
    var labelFont: Font = .system(size: 9, weight: .bold)

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(Theme.spineColors.prefix(7).enumerated()), id: \.offset) { index, color in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(palette.spineOutline, lineWidth: 0.75))
                        .frame(width: 12, height: [40, 34, 44, 38, 42, 30, 36][index])
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            HStack {
                Text("Shelf")
                    .font(labelFont)
                    .foregroundStyle(palette.plateText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(palette.plate, in: RoundedRectangle(cornerRadius: 1))
                Spacer()
                Text("7").font(.system(size: 9)).foregroundStyle(palette.shelfText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(palette.shelf)
        }
        .background(palette.frame, in: RoundedRectangle(cornerRadius: 6))
        .padding(10)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
        .animation(.default, value: palette)
    }
}

#Preview {
    SettingsView()
        .environment(LibraryStore.sample())
        .environment(AuthService(backend: PreviewAuthBackend(
            account: AuthUser(id: UUID(), email: "reader@example.com", name: "Sam Reader"))))
}
