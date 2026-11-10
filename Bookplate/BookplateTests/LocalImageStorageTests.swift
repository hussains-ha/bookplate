import Foundation
import Testing
@testable import Bookplate

struct LocalImageStorageTests {
    private let storage = LocalImageStorage()

    @Test func deleteRemovesASavedImage() throws {
        let url = try storage.save(Data("jpeg".utf8), fileExtension: "jpg")
        #expect(FileManager.default.fileExists(atPath: url.path))
        storage.delete(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func deleteLeavesFilesOutsideItsFolderAlone() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try Data("keep".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        storage.delete(outside)
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func deleteIgnoresWebURLs() {
        storage.delete(URL(string: "https://covers.openlibrary.org/b/isbn/1-L.jpg")!)
    }
}
