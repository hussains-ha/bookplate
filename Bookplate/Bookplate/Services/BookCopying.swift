import Foundation
import Supabase

/// Copies a book from a library shared with you into one of your own (as Want to Read, on its first
/// unlocked shelf). Done on the server so it works without opening the other library.
protocol BookCopying {
    func saveCopy(of bookId: String, from source: UUID, to target: UUID) async throws(BookServiceError)
}

struct SupabaseBookCopying: BookCopying {
    var client: SupabaseClient = SupabaseService.client

    private struct Params: Encodable {
        let p_source_library: UUID
        let p_book_id: String
        let p_target_library: UUID
    }

    func saveCopy(of bookId: String, from source: UUID, to target: UUID) async throws(BookServiceError) {
        try await BookService.requireSession(client)
        do {
            try await client.rpc("save_book_copy", params: Params(p_source_library: source, p_book_id: bookId,
                                                                   p_target_library: target)).execute()
        } catch {
            throw BookService.failure(from: error)
        }
    }
}

enum BookCopyProblem {
    /// What to tell the user when a copy fails. The server reports `already_saved` for a book with the
    /// same title and first author already in that library.
    static func message(for error: BookServiceError, target: String) -> String {
        if case .rejected(let message) = error, message.contains("already_saved") {
            return "\u{201C}\(target)\u{201D} already has this book."
        }
        return "Couldn't save the book. \(error.localizedDescription)"
    }
}

/// For tests and previews.
final class InMemoryBookCopying: BookCopying {
    private(set) var copies: [(bookId: String, source: UUID, target: UUID)] = []
    var error: BookServiceError?

    func saveCopy(of bookId: String, from source: UUID, to target: UUID) async throws(BookServiceError) {
        if let error { throw error }
        copies.append((bookId, source, target))
    }
}
