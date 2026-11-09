import Foundation

/// Saves picked images (custom covers, note photos) and returns a URL the app can show.
protocol ImageStorage {
    func save(_ data: Data, fileExtension: String) throws -> URL
}

/// Keeps images as files in the app's documents folder.
// TODO(supabase): replace with an implementation that uploads to a Supabase storage bucket (per-user folder,
// bucket policies matching the library's row level security) and returns the bucket URL. Also:
//  - local file URLs include the app container path, which can change between installs, so don't persist them;
//  - enforce the size limit from the test plan (M-05: ~6 MB shows "Image too large.");
//  - make uploads safe to interrupt (M-12: no broken cover after force-quit).
struct LocalImageStorage: ImageStorage {
    func save(_ data: Data, fileExtension: String = "jpg") throws -> URL {
        let folder = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("BookplateImages", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(UUID().uuidString.lowercased()).\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }
}
