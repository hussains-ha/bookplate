import SwiftUI

/// Customizes the bookplate (style, size, phrase) and the shelf labels (font, size), with a live preview.
struct BookplateDesignerView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    /// The owner's name, or nil to preview with a placeholder.
    let name: String?
    @State private var design: BookplateDesign

    init(name: String?, design: BookplateDesign) {
        self.name = name
        _design = State(initialValue: design)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BookplateBanner(name: name ?? "Your Name", design: design)
                        // Room for the tallest style, so the form doesn't jump when switching.
                        .frame(minHeight: 96)
                        .padding(.vertical, 12)
                        .animation(.snappy, value: design)
                        .listRowBackground(Theme.background)
                }

                Section("Style") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(BookplateDesign.Style.allCases, id: \.self) { style in
                            choice(style.title, selected: design.style == style) { design.style = style }
                        }
                    }
                    .padding(.vertical, 4)
                    Picker("Size", selection: $design.size) {
                        ForEach(BookplateDesign.Size.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField(design.style.defaultPhrase, text: $design.phrase)
                        .onChange(of: design.phrase) { _, new in
                            if new.count > BookplateDesign.maxPhraseLength {
                                design.phrase = String(new.prefix(BookplateDesign.maxPhraseLength))
                            }
                        }
                } header: {
                    Text("Phrase")
                } footer: {
                    Text("Leave blank to use the style's phrase.")
                }

                Section("Shelf labels") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(BookplateDesign.LabelFont.allCases, id: \.self) { font in
                            // A readable fixed size; the stepper below sets the real label size.
                            let sample = BookplateDesign(labelFont: font, labelSize: 14)
                            choice(font.title, font: sample.shelfLabelFont(), selected: design.labelFont == font) {
                                design.labelFont = font
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Stepper(value: $design.labelSize, in: BookplateDesign.labelSizes) {
                        Text("Size \(design.labelSize) pt")
                    }
                    labelPreview
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Bookplate")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.setBookplate(design)
                        dismiss()
                    }
                }
            }
        }
        .tint(Theme.brown)
    }

    private func choice(_ title: String, font: Font = .subheadline.weight(.medium), selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(selected ? .white : Theme.brown)
                .background(selected ? Theme.brown : Theme.brown.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A shelf strip with a name plate in the chosen label font and size.
    private var labelPreview: some View {
        HStack {
            Text("Fiction & Classics")
                .font(design.shelfLabelFont())
                .foregroundStyle(palette.plateText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(palette.plate, in: RoundedRectangle(cornerRadius: 1))
            Spacer()
            Text("12").font(.system(size: 9)).foregroundStyle(palette.shelfText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(palette.shelf, in: RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

#Preview {
    BookplateDesignerView(name: "Sam Reader", design: BookplateDesign())
        .environment(LibraryStore.sample())
}
