import Foundation

/// Custom covers and note photos picked on this device, saved per user as file names inside the
/// image folder (the app container path can change). A local cover wins over the stored copy,
/// so it shows at once and while its upload is pending. Note photos stay on the device only.
// TODO(supabase): note photos are device-only; move them to Storage too if they should sync.
struct LocalBookFiles {
    struct Entry: Codable, Equatable {
        var customCover: String?
        var notePhotos: [String] = []
    }

    let fileURL: URL
    let imagesFolder: URL

    /// The file for a user, under Application Support.
    static func forUser(_ userId: UUID) throws -> LocalBookFiles {
        LocalBookFiles(fileURL: try userFolder(userId).appendingPathComponent("local-files.json"),
                       imagesFolder: try LocalImageStorage.folder())
    }

    /// Application Support/Bookplate/<user id>, created if needed.
    static func userFolder(_ userId: UUID) throws -> URL {
        let folder = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Bookplate/\(userId.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Fills in each meta's custom cover and note photos from the saved file.
    func apply(to metas: [BookMeta]) -> [BookMeta] {
        let entries = load()
        return metas.map { meta in
            guard let entry = entries[meta.bookId] else { return meta }
            var meta = meta
            // A missing file (e.g. a reinstall) falls back to the stored cover from the server.
            if let local = entry.customCover.map(url), FileManager.default.fileExists(atPath: local.path) {
                meta.customCover = local
            }
            meta.notePhotos = entry.notePhotos.map(url)
            return meta
        }
    }

    /// Saves the custom covers and note photos of `metas`, replacing what was saved before.
    func save(_ metas: [BookMeta]) {
        var entries: [String: Entry] = [:]
        for meta in metas where meta.customCover != nil || !meta.notePhotos.isEmpty {
            entries[meta.bookId] = Entry(customCover: meta.customCover.flatMap { $0.isFileURL ? $0.lastPathComponent : nil },
                                         notePhotos: meta.notePhotos.map(\.lastPathComponent))
        }
        try? JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }

    func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private func url(_ name: String) -> URL {
        imagesFolder.appendingPathComponent(name)
    }
}
