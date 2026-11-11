import PhotosUI
import SwiftUI

/// Everything about one book: its cover, the user's status, rating, notes, photos, tags and lists.
struct BookDetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AuthService.self) private var auth: AuthService?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(LibrarySession.self) private var session: LibrarySession?
    var bookCopying: BookCopying = SupabaseBookCopying()
    @State private var copyResult: String?

    let bookId: String
    var imageStorage: ImageStorage = LocalImageStorage()

    @AppStorage("skipRemoveBookConfirmation") private var skipRemoveConfirmation = false
    @State private var showingRemoveConfirmation = false
    @State private var coverItem: PhotosPickerItem?
    @State private var showingCoverLibrary = false
    @State private var showingCamera = false
    @State private var showingCameraDenied = false
    @State private var showingCoverError = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var newTag = ""

    private static let gold = Color(red: 0.78, green: 0.58, blue: 0.20)

    var body: some View {
        NavigationStack {
            Group {
                if let book = store.book(withId: bookId), let meta = store.meta(for: bookId) {
                    content(book, meta)
                } else {
                    Color.clear
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Book")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: store.book(withId: bookId) == nil) { _, removed in
            if removed { dismiss() }
        }
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task { await setCover(from: item) }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(from: items) }
        }
        .photosPicker(isPresented: $showingCoverLibrary, selection: $coverItem, matching: .images)
        #if os(iOS)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                showingCamera = false
                if let image { setCover(fromCamera: image) }
            }
            .ignoresSafeArea()
        }
        #endif
        .alert("Camera access is off", isPresented: $showingCameraDenied) {
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            #endif
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To take a cover photo, allow camera access for Bookplate in Settings.")
        }
        .alert("Couldn't use that photo", isPresented: $showingCoverError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a different photo.")
        }
        .sheet(isPresented: $showingRemoveConfirmation) {
            RemoveBookConfirmation(skipNextTime: $skipRemoveConfirmation, onRemove: removeBook)
                .presentationDetents([.height(280)])
        }
    }

    private var canChangeCover: Bool { store.library?.isOwned ?? true }

    /// "Save to my library": copies a friend's book into one of your libraries.
    @ViewBuilder private func saveCopyButton(_ source: LibraryInfo) -> some View {
        let targets = session?.owned ?? []
        Menu {
            ForEach(targets) { target in
                Button(target.name) { saveCopy(from: source, to: target) }
            }
        } label: {
            Label("Save to My Library", systemImage: "square.and.arrow.down")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        } primaryAction: {
            if targets.count == 1, let target = targets.first { saveCopy(from: source, to: target) }
        }
        .buttonStyle(.bordered)
        .tint(Theme.brown)
        .disabled(targets.isEmpty)
        .alert("Save to My Library", isPresented: Binding(get: { copyResult != nil }, set: { if !$0 { copyResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(copyResult ?? "")
        }
    }

    private func saveCopy(from source: LibraryInfo, to target: LibraryInfo) {
        Task {
            do throws(BookServiceError) {
                try await bookCopying.saveCopy(of: bookId, from: source.id, to: target.id)
                copyResult = "Saved to \u{201C}\(target.name)\u{201D} as Want to Read."
            } catch {
                copyResult = BookCopyProblem.message(for: error, target: target.name)
            }
        }
    }

    // MARK: Sections

    private func content(_ book: Book, _ meta: BookMeta) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let owner = BookplateBanner.ownerName(auth?.user, library: store.library) {
                    BookplateBanner(name: owner, design: store.settings.bookplate, compact: true)
                }
                header(book, meta)
                if let library = store.library, !library.isOwned {
                    saveCopyButton(library)
                }
                // A library shared with you as View only: everything shows, nothing changes.
                Group {
                    section("Status") { statusPicker(meta) }
                    section("Rating") { StarRating(rating: meta.rating, gold: Self.gold) { store.setRating($0, for: bookId) } }
                    section("Tags") { tags(meta) }
                    section("Lists") { lists() }
                    section("Notes") { notes(meta) }
                    section("Photos") { photos(meta) }
                }
                .disabled(!store.canEdit)

                if store.canEdit {
                    Button("Remove Book", role: .destructive) {
                        if skipRemoveConfirmation { removeBook() } else { showingRemoveConfirmation = true }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                }
            }
            .padding(16)
        }
    }

    private func header(_ book: Book, _ meta: BookMeta) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                BookCoverView(book: book, meta: meta)
                    .frame(width: 104)
                    .overlay(alignment: .bottomTrailing) {
                        // Custom covers are stored in the owner's folder, so only the owner changes them.
                        if canChangeCover { Menu {
                            coverMenu(hasCustomCover: meta.customCover != nil)
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Theme.brown))
                                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.5))
                        }
                        .offset(x: 8, y: 8)
                        .accessibilityLabel("Change cover") }
                    }
                if canChangeCover {
                    Menu {
                        coverMenu(hasCustomCover: meta.customCover != nil)
                    } label: {
                        Text("Change Cover").font(.caption.weight(.semibold))
                    }
                    .padding(.top, 6)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(Theme.title(24))
                    .foregroundStyle(Theme.brown)
                if !book.authors.isEmpty {
                    Text(book.authors.joined(separator: ", "))
                        .foregroundStyle(Theme.mutedText)
                }
                let shelves = store.shelves(containing: bookId)
                if !shelves.isEmpty {
                    Text("On: " + shelves.map(\.name).joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Theme.mutedText)
                }
                if KindleLink.isInstalled() {
                    Button { openURL(KindleLink.url) } label: {
                        Label("Open in Kindle", systemImage: "book")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.brown)
                    .padding(.top, 6)
                }
            }
        }
    }

    private func statusPicker(_ meta: BookMeta) -> some View {
        Picker("Status", selection: Binding(
            get: { meta.status },
            set: { store.setStatus($0, for: bookId) }
        )) {
            Text("Want").tag(BookMeta.Status.want)
            Text("Reading").tag(BookMeta.Status.reading)
            Text("Read").tag(BookMeta.Status.read)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func tags(_ meta: BookMeta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(meta.tags, id: \.self) { tag in
                    chip(tag, removeLabel: "Remove tag \(tag)") { store.removeTag(tag, from: bookId) }
                }
            }
            TextField("Add a tag", text: $newTag)
                .authFieldStyle()
                .onSubmit {
                    store.addTag(newTag, to: bookId)
                    newTag = ""
                }
        }
    }

    private func lists() -> some View {
        let member = store.lists(containing: bookId)
        let others = store.lists.filter { list in !member.contains { $0.id == list.id } }
        return VStack(alignment: .leading, spacing: 8) {
            if store.lists.isEmpty {
                Text("No lists yet.").font(.footnote).foregroundStyle(Theme.mutedText)
            }
            FlowLayout(spacing: 6) {
                ForEach(member) { list in
                    chip(list.name, removeLabel: "Remove from \(list.name)") {
                        store.setBook(bookId, inList: list.id, to: false)
                    }
                }
            }
            if !others.isEmpty {
                Menu("Add to list") {
                    ForEach(others) { list in
                        Button(list.name) { store.setBook(bookId, inList: list.id, to: true) }
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func notes(_ meta: BookMeta) -> some View {
        TextField("Personal notes", text: Binding(
            get: { meta.notes ?? "" },
            set: { store.setNotes($0, for: bookId) }
        ), axis: .vertical)
        .lineLimit(3...8)
        .authFieldStyle()
    }

    private func photos(_ meta: BookMeta) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !meta.notePhotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(meta.notePhotos, id: \.self) { url in
                            CachedImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Theme.field
                            }
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contextMenu {
                                Button("Remove Photo", systemImage: "trash", role: .destructive) {
                                    store.removeNotePhoto(url, from: bookId)
                                }
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $photoItems, matching: .images) {
                Label("Add Photos", systemImage: "photo.badge.plus").font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: Pieces

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.mutedText)
            content()
        }
    }

    private func chip(_ title: String, removeLabel: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Button(action: onRemove) { Image(systemName: "xmark").font(.caption2) }
                .accessibilityLabel(removeLabel)
        }
        .font(.footnote)
        .foregroundStyle(Theme.brown)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.field, in: Capsule())
        .overlay(Capsule().stroke(Theme.brown.opacity(0.25)))
    }

    // MARK: Actions

    private func removeBook() {
        store.removeBook(bookId)
        dismiss()
    }

    @ViewBuilder
    private func coverMenu(hasCustomCover: Bool) -> some View {
        #if os(iOS)
        if CameraAccess.current() != .unavailable {
            Button("Take Photo", systemImage: "camera") { Task { await openCamera() } }
        }
        #endif
        Button("Choose from Library", systemImage: "photo.on.rectangle") { showingCoverLibrary = true }
        if hasCustomCover {
            Button("Remove Custom Cover", systemImage: "trash", role: .destructive) {
                replaceCustomCover(with: nil)
            }
        }
    }

    #if os(iOS)
    private func openCamera() async {
        if await CameraAccess.request() {
            showingCamera = true
        } else {
            showingCameraDenied = true
        }
    }

    private func setCover(fromCamera image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 1) else { showingCoverError = true; return }
        saveCover(data)
    }
    #endif

    private func setCover(from item: PhotosPickerItem) async {
        defer { coverItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { showingCoverError = true; return }
        saveCover(data)
    }

    /// Shrinks the photo to a ~1000px JPEG, saves it and points the book's custom cover at it.
    // TODO(supabase): upload to the covers bucket (#36) and show upload errors.
    private func saveCover(_ data: Data) {
        guard let jpeg = ImageCompressor.jpeg(from: data),
              let url = try? imageStorage.save(jpeg, fileExtension: "jpg")
        else { showingCoverError = true; return }
        replaceCustomCover(with: url)
    }

    /// Sets or clears the custom cover and deletes the replaced photo's file.
    /// (A removed book keeps its cover file, so undo can bring it back.)
    private func replaceCustomCover(with url: URL?) {
        let old = store.meta(for: bookId)?.customCover
        store.setCustomCover(url, for: bookId)
        if let old, old != url { imageStorage.delete(old) }
    }

    private func addPhotos(from items: [PhotosPickerItem]) async {
        defer { photoItems = [] }
        for item in items {
            guard let (data, ext) = await load(item), let url = try? imageStorage.save(data, fileExtension: ext) else { continue }
            store.addNotePhoto(url, to: bookId)
        }
    }

    private func load(_ item: PhotosPickerItem) async -> (Data, String)? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return (data, item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")
    }
}

private struct StarRating: View {
    let rating: Int?
    let gold: Color
    let onChange: (Int?) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onChange(rating == star ? nil : star)
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(star <= (rating ?? 0) ? gold : Theme.mutedText.opacity(0.6))
                }
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
            }
        }
        .buttonStyle(.plain)
    }
}

/// A small confirmation with a "don't ask again" choice (the built-in dialogs can't hold a toggle).
private struct RemoveBookConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var skipNextTime: Bool
    let onRemove: () -> Void

    /// Only saved to `skipNextTime` when the book is actually removed, so cancelling doesn't switch the prompt off.
    @State private var dontAskAgain = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Remove this book?")
                .font(Theme.title(20))
                .foregroundStyle(Theme.brown)
            Text("It will be removed from every shelf and list, along with your notes and rating.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.mutedText)
            Toggle("Don't show this again", isOn: $dontAskAgain)
                .font(.subheadline)
            Button("Remove Book", role: .destructive) {
                skipNextTime = dontAskAgain
                dismiss()
                onRemove()
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel") { dismiss() }
        }
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Wraps its children onto new lines, for tag and list chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

#Preview {
    BookDetailView(bookId: "book-atomic-habits")
        .environment(LibraryStore.sample())
}
