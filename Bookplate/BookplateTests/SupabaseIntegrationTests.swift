import Foundation
import Supabase
import Testing
@testable import Bookplate

/// Runs the real Supabase repository against the project. Skipped unless credentials for a
/// confirmed throwaway account are passed in, e.g.:
/// `TEST_RUNNER_BOOKPLATE_E2E_EMAIL=… TEST_RUNNER_BOOKPLATE_E2E_PASSWORD=… xcodebuild test …`
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BOOKPLATE_E2E_EMAIL"] != nil), .serialized)
struct SupabaseIntegrationTests {
    @Test func libraryRoundTripsThroughSupabase() async throws {
        let env = ProcessInfo.processInfo.environment
        let auth = SupabaseService.client.auth
        let session = try await auth.signIn(email: env["BOOKPLATE_E2E_EMAIL"]!, password: env["BOOKPLATE_E2E_PASSWORD"]!)
        defer { Task { try? await auth.signOut() } }

        let repo = SupabaseLibraryRepository(userId: session.user.id)
        let suffix = UUID().uuidString.lowercased()
        let book = Book(id: "book-\(suffix)", title: "Integration", authors: ["Tester"], pageCount: 10,
                        coverUrl: URL(string: "https://example.com/c.jpg"), isbn13: nil)
        let other = Book(id: "book-2-\(suffix)", title: "Other", authors: [], pageCount: nil, coverUrl: nil, isbn13: nil)
        var meta = BookMeta(bookId: book.id, status: "reading", rating: 4, notes: "n", notePhotos: [], tags: ["t"],
                            customCover: nil, addedDate: Date(), startedDate: Date(), finishedDate: nil)
        let shelf = Shelf(id: "shelf-\(suffix)", name: "Integration shelf", bookIds: [], isLocked: true)
        let list = BookList(id: "list-\(suffix)", name: "Integration list", bookIds: [])

        for change: LibraryChange in [
            .saveBook(book), .saveBook(other), .saveMeta(meta),
            .saveShelf(shelf, position: 0), .setShelfBooks(shelfId: shelf.id, bookIds: [other.id, book.id]),
            .saveList(list, position: 0), .setListBooks(listId: list.id, bookIds: [book.id]),
        ] {
            try await repo.apply(change)
        }
        // Upserts update in place.
        meta.rating = 5
        try await repo.apply(.saveMeta(meta))
        // Clearing values must clear them on the server too.
        var cleared = meta
        cleared.notes = nil
        cleared.startedDate = nil
        try await repo.apply(.saveMeta(cleared))
        var renamed = book
        renamed.pageCount = 11
        try await repo.apply(.saveBook(renamed))

        let snapshot = try await repo.loadLibrary()
        #expect(snapshot.books.first { $0.id == book.id } == renamed)
        #expect(snapshot.metas.first { $0.bookId == book.id }?.rating == 5)
        #expect(snapshot.metas.first { $0.bookId == book.id }?.notes == nil)
        #expect(snapshot.metas.first { $0.bookId == book.id }?.startedDate == nil)

        // A repository bound to another account refuses to write.
        await #expect(throws: BookServiceError.notSignedIn) {
            try await SupabaseLibraryRepository(userId: UUID()).apply(.saveBook(book))
        }
        // Unknown books are skipped when replacing a shelf's books.
        try await repo.apply(.setShelfBooks(shelfId: shelf.id, bookIds: ["book-ghost", other.id, book.id]))
        #expect(snapshot.shelves.first { $0.id == shelf.id }?.bookIds == [other.id, book.id])
        #expect(snapshot.shelves.first { $0.id == shelf.id }?.isLocked == true)
        #expect(snapshot.lists.first { $0.id == list.id }?.bookIds == [book.id])

        // Deleting books cascades to details and memberships.
        try await repo.apply(.deleteBook(id: book.id))
        try await repo.apply(.deleteBook(id: other.id))
        let after = try await repo.loadLibrary()
        #expect(!after.metas.contains { $0.bookId == book.id })
        #expect(after.shelves.first { $0.id == shelf.id }?.bookIds == [])
    }
}
