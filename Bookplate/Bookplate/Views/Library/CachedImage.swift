import SwiftUI

/// An image loaded through `CoverImageLoader`: cached, download-limited and downsampled to its displayed size.
/// Loading starts when the view appears and is cancelled when it disappears.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    var loader: CoverImageLoader = .shared
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (url: URL, image: CGImage)?

    var body: some View {
        GeometryReader { proxy in
            let pixels = Self.pixelSize(for: proxy.size, scale: displayScale)
            Group {
                if let loaded, loaded.url == url {
                    content(Image(decorative: loaded.image, scale: displayScale))
                        .transition(.opacity)
                } else {
                    placeholder()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: TaskKey(url: url, pixels: pixels)) {
                guard let url, pixels > 0 else { return }
                guard let image = try? await loader.image(for: url, maxPixelSize: pixels) else { return }
                withAnimation(.easeIn(duration: 0.25)) { loaded = (url, image) }
            }
        }
    }

    private struct TaskKey: Equatable {
        let url: URL?
        let pixels: Int
    }

    /// Longest displayed side in pixels, rounded up to a 50px step so tiny layout changes don't reload.
    static func pixelSize(for size: CGSize, scale: CGFloat) -> Int {
        let longest = max(size.width, size.height) * scale
        guard longest > 0 else { return 0 }
        return Int((longest / 50).rounded(.up)) * 50
    }
}
