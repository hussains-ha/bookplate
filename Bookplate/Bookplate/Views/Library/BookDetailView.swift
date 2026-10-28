import PhotosUI
import SwiftUI

/// Everything about one book: its cover, the user's status, rating, notes, photos, tags and lists.
struct BookDetailView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let bookId: String
    var imageStorage: ImageStorage = LocalImageStorage()

    @AppStorage("skipRemoveBookConfirmation") private var skipRemoveConfirmation = false
    @State private var showingRemoveConfirmation = false
    @State private var coverItem: PhotosPickerItem?
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
        .sheet(isPresented: $showingRemoveConfirmation) {
            RemoveBookConfirmation(skipNextTime: $skipRemoveConfirmation, onRemove: removeBook)
                .presentationDetents([.height(280)])
        }
    }

    // MARK: Sections

    private func content(_ book: Book, _ meta: BookMeta) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(book, meta)
                section("Status") { statusPicker(meta) }
                section("Rating") { StarRating(rating: meta.rating, gold: Self.gold) { store.setRating($0, for: bookId) } }
                section("Tags") { tags(meta) }
                section("Lists") { lists() }
                section("Notes") { notes(meta) }
                section("Photos") { photos(meta) }

                Button("Remove Book", role: .destructive) {
                    if skipRemoveConfirmation { removeBook() } else { showingRemoveConfirmation = true }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
            }
            .padding(16)
        }
    }

    private func header(_ book: Book, _ meta: BookMeta) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                BookCoverView(book: book, meta: meta)
                    .frame(width: 104)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                PhotosPicker(selection: $coverItem, matching: .images) {
                    Text("Change Cover").font(.caption.weight(.semibold))
                }
                if meta.customCover != nil {
                    Button("Reset Cover") { store.setCustomCover(nil, for: bookId) }
                        .font(.caption)
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
                            AsyncImage(url: url) { image in
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

    // A picked image that can't be read or saved is skipped silently for now.
    // TODO(supabase): show "Image too large." / upload errors once images go to a storage bucket.
    private func setCover(from item: PhotosPickerItem) async {
        defer { coverItem = nil }
        guard let (data, ext) = await load(item), let url = try? imageStorage.save(data, fileExtension: ext) else { return }
        store.setCustomCover(url, for: bookId)
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Remove this book?")
                .font(Theme.title(20))
                .foregroundStyle(Theme.brown)
            Text("It will be removed from every shelf and list, along with your notes and rating.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.mutedText)
            Toggle("Don't show this again", isOn: $skipNextTime)
                .font(.subheadline)
            Button("Remove Book", role: .destructive) {
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
