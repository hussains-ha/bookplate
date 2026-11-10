import Foundation
import Supabase

/// Where custom covers are kept online: the private `book-covers` bucket, one file per book
/// at `{user id}/{book id}.jpg`. Storage policies let each user reach only their own folder.
nonisolated protocol CoverStorage: Sendable {
    func upload(_ data: Data, path: String) async throws
    func remove(path: String) async throws
    func download(path: String) async throws -> Data
}

nonisolated struct SupabaseCoverStorage: CoverStorage {
    static let bucket = "book-covers"
    let client: SupabaseClient

    func upload(_ data: Data, path: String) async throws {
        try await client.storage.from(Self.bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
    }

    func remove(path: String) async throws {
        _ = try await client.storage.from(Self.bucket).remove(paths: [path])
    }

    func download(path: String) async throws -> Data {
        try await client.storage.from(Self.bucket).download(path: path)
    }
}

/// How a stored custom cover is named.
/// - The bucket object is `{user id}/{book id}.jpg`.
/// - `book_meta.custom_cover` holds that path plus `?v=<version>`, so a replaced cover gets a new
///   URL and isn't shown from an old cache entry.
/// - In the app (`BookMeta.customCover`) it's the URL `bookplate-cover://covers/{user id}/{book id}.jpg?v=<version>`,
///   which `CoverImageLoader` downloads through `CoverStorage`.
nonisolated enum CustomCoverPath {
    static let scheme = "bookplate-cover"

    static func objectPath(userId: UUID, bookId: String) -> String {
        "\(userId.uuidString.lowercased())/\(bookId).jpg"
    }

    static func columnValue(userId: UUID, bookId: String, version: String) -> String {
        "\(objectPath(userId: userId, bookId: bookId))?v=\(version)"
    }

    /// The app URL for a `custom_cover` column value.
    static func url(columnValue: String) -> URL? {
        URL(string: "\(scheme)://covers/\(columnValue)")
    }

    /// The bucket object path of a stored-cover URL, or nil for any other URL.
    static func objectPath(from url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        return path.isEmpty ? nil : path
    }

    /// The version for a newly picked cover: its local file name without the extension.
    static func version(fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
    }
}
