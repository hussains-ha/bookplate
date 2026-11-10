import Foundation
import ImageIO
import Testing
import SwiftUI
import UIKit
@testable import Bookplate

struct CoverImageLoaderTests {
    /// Serves a fixed image (or error), optionally after a delay, and tracks how many requests run at once.
    final class ImageServer: HTTPClient, @unchecked Sendable {
        private let lock = NSLock()
        private var _requests = 0
        private var _running = 0
        private var _maxRunning = 0
        var status = 200
        var body: Data
        var delay: Duration = .zero

        init(body: Data) { self.body = body }

        var requests: Int { lock.withLock { _requests } }
        var maxRunning: Int { lock.withLock { _maxRunning } }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            lock.withLock {
                _requests += 1
                _running += 1
                _maxRunning = max(_maxRunning, _running)
            }
            defer { lock.withLock { _running -= 1 } }
            if delay > .zero { try await Task.sleep(for: delay) }
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    static func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("covers-\(UUID().uuidString)", isDirectory: true)
    }

    private let url = URL(string: "https://covers.example.com/1.jpg")!

    @Test func secondLoadComesFromCache() async throws {
        let server = ImageServer(body: Self.png(width: 200, height: 300))
        let loader = CoverImageLoader(client: server, cacheFolder: tempFolder())
        _ = try await loader.image(for: url, maxPixelSize: 300)
        _ = try await loader.image(for: url, maxPixelSize: 300)
        _ = try await loader.image(for: url, maxPixelSize: 100)
        #expect(server.requests == 1)
    }

    @Test func diskCacheSurvivesARelaunch() async throws {
        let folder = tempFolder()
        let server = ImageServer(body: Self.png(width: 200, height: 300))
        _ = try await CoverImageLoader(client: server, cacheFolder: folder).image(for: url, maxPixelSize: 300)

        // "Relaunch" while offline: a new loader, and the network now fails.
        server.status = 503
        let image = try await CoverImageLoader(client: server, cacheFolder: folder).image(for: url, maxPixelSize: 300)
        #expect(image.height == 300)
        #expect(server.requests == 1)
    }

    @Test func failedURLIsNotRetriedThisSessionButIsAfterRelaunch() async throws {
        let folder = tempFolder()
        let server = ImageServer(body: Data())
        server.status = 404
        let loader = CoverImageLoader(client: server, cacheFolder: folder)
        await #expect(throws: (any Error).self) { try await loader.image(for: url, maxPixelSize: 300) }
        await #expect(throws: (any Error).self) { try await loader.image(for: url, maxPixelSize: 300) }
        #expect(server.requests == 1)
        #expect(await loader.hasFailed(url))

        server.status = 200
        server.body = Self.png(width: 20, height: 30)
        _ = try await CoverImageLoader(client: server, cacheFolder: folder).image(for: url, maxPixelSize: 300)
        #expect(server.requests == 2)
    }

    @Test func nonImageResponseCountsAsFailed() async {
        let server = ImageServer(body: Data("<html>".utf8))
        let loader = CoverImageLoader(client: server, cacheFolder: tempFolder())
        await #expect(throws: (any Error).self) { try await loader.image(for: url, maxPixelSize: 300) }
        #expect(await loader.hasFailed(url))
    }

    @Test func atMostFourDownloadsRunAtOnce() async throws {
        let server = ImageServer(body: Self.png(width: 10, height: 15))
        server.delay = .milliseconds(30)
        let loader = CoverImageLoader(client: server, cacheFolder: tempFolder())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    _ = try await loader.image(for: URL(string: "https://covers.example.com/\(index).jpg")!, maxPixelSize: 50)
                }
            }
            try await group.waitForAll()
        }
        #expect(server.requests == 12)
        #expect(server.maxRunning == 4)
    }

    @Test func cancelledLoadIsNotMarkedFailedAndFreesItsSlot() async throws {
        let server = ImageServer(body: Self.png(width: 10, height: 15))
        server.delay = .seconds(5)
        let loader = CoverImageLoader(client: server, cacheFolder: tempFolder(), maxConcurrentDownloads: 1)
        let task = Task { try await loader.image(for: url, maxPixelSize: 50) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await !loader.hasFailed(url))

        // The single slot is free again, so another download goes through.
        server.delay = .zero
        _ = try await loader.image(for: URL(string: "https://covers.example.com/other.jpg")!, maxPixelSize: 50)
    }

    @Test func downsamplesToTheDisplaySize() async throws {
        let server = ImageServer(body: Self.png(width: 1000, height: 1500))
        let loader = CoverImageLoader(client: server, cacheFolder: tempFolder())
        let thumb = try await loader.image(for: url, maxPixelSize: 150)
        #expect(thumb.height == 150)
        #expect(thumb.width == 100)
        let large = try await loader.image(for: url, maxPixelSize: 3000)
        #expect(large.height == 1500) // never upscaled
    }

    @Test func localFilesSkipTheNetwork() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Self.png(width: 40, height: 60).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let server = ImageServer(body: Data())
        let image = try await CoverImageLoader(client: server, cacheFolder: tempFolder()).image(for: file, maxPixelSize: 30)
        #expect(image.height == 30)
        #expect(server.requests == 0)
    }

    @Test func pixelSizeRoundsUpToFiftyPixelSteps() {
        #expect(CachedImage<EmptyView, EmptyView>.pixelSize(for: CGSize(width: 104, height: 156), scale: 3) == 500)
        #expect(CachedImage<EmptyView, EmptyView>.pixelSize(for: CGSize(width: 84, height: 84), scale: 2) == 200)
        #expect(CachedImage<EmptyView, EmptyView>.pixelSize(for: .zero, scale: 3) == 0)
    }
}
