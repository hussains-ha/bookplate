import CryptoKit
import Foundation
import ImageIO

/// Loads cover images (and other images the app shows) with a memory + disk cache.
/// - Downloads go to a disk cache, so covers show instantly on relaunch and offline.
/// - At most `maxConcurrentDownloads` downloads run at once.
/// - A URL that failed isn't retried until the next launch (a new loader).
/// - Images are downsampled to the pixel size they're shown at.
/// - Local file URLs (custom covers, note photos) are read from disk, without the download limit.
actor CoverImageLoader {
    static let shared = CoverImageLoader()

    enum LoadError: Error {
        case failedThisSession
        case badResponse
        case notAnImage
    }

    let maxConcurrentDownloads: Int
    private let client: HTTPClient
    private let cacheFolder: URL?
    private let memory = NSCache<NSString, CGImage>()
    private var failed: Set<URL> = []
    private var activeDownloads = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(client: HTTPClient = URLSessionHTTPClient(), cacheFolder: URL? = CoverImageLoader.defaultCacheFolder(),
         maxConcurrentDownloads: Int = 4) {
        self.client = client
        self.cacheFolder = cacheFolder
        self.maxConcurrentDownloads = maxConcurrentDownloads
        memory.countLimit = 300
        if let cacheFolder {
            try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        }
    }

    static func defaultCacheFolder() -> URL? {
        try? FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("CoverImages", isDirectory: true)
    }

    /// The image at `url`, downsampled so its longest side is at most `maxPixelSize` pixels.
    /// Throws `CancellationError` if the calling task is cancelled (e.g. the view scrolled away).
    func image(for url: URL, maxPixelSize: Int) async throws -> CGImage {
        let key = "\(url.absoluteString)|\(maxPixelSize)" as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if failed.contains(url) { throw LoadError.failedThisSession }

        let data = try await imageData(for: url)
        guard let image = Self.downsample(data, maxPixelSize: maxPixelSize) else {
            failed.insert(url)
            throw LoadError.notAnImage
        }
        memory.setObject(image, forKey: key)
        return image
    }

    /// Whether `url` failed this session (for tests and diagnostics).
    func hasFailed(_ url: URL) -> Bool { failed.contains(url) }

    // MARK: Data

    private func imageData(for url: URL) async throws -> Data {
        if url.isFileURL {
            do { return try Data(contentsOf: url) } catch { failed.insert(url); throw error }
        }
        if let file = cacheFile(for: url), let data = try? Data(contentsOf: file) { return data }

        try await acquireDownloadSlot()
        defer { releaseDownloadSlot() }
        // Another view may have downloaded it while this one waited.
        if let file = cacheFile(for: url), let data = try? Data(contentsOf: file) { return data }
        try Task.checkCancellation()

        let data: Data
        do {
            let (body, response) = try await client.data(for: URLRequest(url: url))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw LoadError.badResponse
            }
            data = body
        } catch {
            // A cancelled load (view went away) isn't a broken URL; try again next time it's shown.
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            failed.insert(url)
            throw error
        }
        guard CGImageSourceCreateWithData(data as CFData, nil).map(CGImageSourceGetCount) ?? 0 > 0 else {
            failed.insert(url)
            throw LoadError.notAnImage
        }
        if let file = cacheFile(for: url) { try? data.write(to: file, options: .atomic) }
        return data
    }

    private func cacheFile(for url: URL) -> URL? {
        guard let cacheFolder else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return cacheFolder.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
    }

    // MARK: Download limit

    private func acquireDownloadSlot() async throws {
        if activeDownloads < maxConcurrentDownloads {
            activeDownloads += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
        // The slot was handed over by `releaseDownloadSlot`, so `activeDownloads` already counts it.
        if Task.isCancelled {
            releaseDownloadSlot()
            throw CancellationError()
        }
    }

    private func releaseDownloadSlot() {
        if waiting.isEmpty {
            activeDownloads -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }

    // MARK: Downsampling

    /// Decodes `data` at no more than `maxPixelSize` on its longest side (never upscaled), with orientation applied.
    static func downsample(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        var size = maxPixelSize
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int {
            size = min(maxPixelSize, max(width, height))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
