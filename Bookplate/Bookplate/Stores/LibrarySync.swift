import Foundation
import Observation

/// Saves library changes in order, one at a time. A failed save stays at the front of the
/// queue and is retried with backoff; changes the database refuses are dropped and reported.
/// The queue is written to `pendingFile` on every change, so nothing is lost if the app quits.
@Observable
final class LibrarySync {
    enum Status: Equatable {
        case idle
        case saving
        /// Saving failed; the change will be retried.
        case retrying(String)
        /// The database refused a change; it was dropped.
        case rejected(String)
    }

    /// Retrying wins over a rejection notice, which stays until dismissed.
    var status: Status {
        if let retryMessage { return .retrying(retryMessage) }
        if let rejection { return .rejected(rejection) }
        return worker == nil ? .idle : .saving
    }

    private(set) var pending: [LibraryChange] = [] {
        didSet { if !stopped { pendingFile?.save(pending) } }
    }
    private var retryMessage: String?
    private var rejection: String?

    let repository: LibraryRepository
    private let pendingFile: PendingChangesFile?
    private let retryDelays: [Duration]
    private let sleep: (Duration) async throws -> Void
    private var worker: Task<Void, Never>?
    private var retryWait: Task<Void, Never>?
    /// The change being sent right now, which must not be replaced while in flight.
    private var sending = false
    private var stopped = false

    init(repository: LibraryRepository,
         pendingFile: PendingChangesFile? = nil,
         retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30)],
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.repository = repository
        self.pendingFile = pendingFile
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    func enqueue(contentsOf changes: [LibraryChange]) {
        for change in changes { enqueue(change) }
    }

    func enqueue(_ change: LibraryChange) {
        guard !stopped else { return }
        // Typing notes or dragging books produces a burst of saves for the same item;
        // only the latest matters, so replace a queued one that hasn't been sent yet.
        if let last = pending.last, last.replaces(change) == true, !(sending && pending.count == 1) {
            pending[pending.count - 1] = change
        } else {
            pending.append(change)
        }
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    /// Skips the current backoff wait.
    func retryNow() {
        retryWait?.cancel()
    }

    /// Clears the "refused" notice.
    func dismissRejection() {
        rejection = nil
    }

    /// Stops saving for good (sign-out or account switch). Unsent changes stay in `pendingFile`
    /// and are sent on the account's next sign-in.
    func stop() {
        stopped = true
        worker?.cancel()
        retryWait?.cancel()
        pending = []
        retryMessage = nil
    }

    /// Waits until every queued change has been saved or dropped. For tests.
    func waitUntilIdle() async {
        while let worker { await worker.value }
    }

    private func drain() async {
        var failures = 0
        while !stopped, let change = pending.first {
            sending = true
            let result: Result<Void, BookServiceError>
            do {
                try await repository.apply(change)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            sending = false
            guard !stopped else { break }
            switch result {
            case .success:
                pending.removeFirst()
                failures = 0
                retryMessage = nil
            case .failure(.rejected(let message)):
                pending.removeFirst()
                retryMessage = nil
                rejection = "Couldn't save a change: \(message)"
            case .failure(let error):
                retryMessage = error.localizedDescription
                let delay = retryDelays[min(failures, retryDelays.count - 1)]
                failures += 1
                let wait = Task { [sleep] in _ = try? await sleep(delay) }
                retryWait = wait
                await wait.value
                retryWait = nil
            }
        }
        worker = nil
    }
}

private extension LibraryChange {
    /// True when `other` saves the same item and makes this change redundant.
    func replaces(_ other: LibraryChange) -> Bool {
        switch (self, other) {
        case (.saveMeta(let a), .saveMeta(let b)): a.bookId == b.bookId
        case (.setShelfBooks(let a, _), .setShelfBooks(let b, _)): a == b
        case (.setListBooks(let a, _), .setListBooks(let b, _)): a == b
        case (.saveSettings, .saveSettings): true
        // Only the latest cover choice for a book matters.
        case (.uploadCover(let a, _), .uploadCover(let b, _)), (.uploadCover(let a, _), .deleteCover(let b)),
             (.deleteCover(let a), .uploadCover(let b, _)), (.deleteCover(let a), .deleteCover(let b)): a == b
        default: false
        }
    }
}
/// Changes not yet confirmed by the server, saved per user so they survive quitting the app.
struct PendingChangesFile {
    let fileURL: URL

    /// Before #123 there was one library per user and one file for it. It now belongs to the
    /// user's first library and is merged into that library's file the next time it opens.
    static func forUser(_ userId: UUID) throws -> PendingChangesFile {
        PendingChangesFile(fileURL: try LocalBookFiles.userFolder(userId).appendingPathComponent("pending-changes.json"))
    }

    /// One file per library, so a change is only ever sent to the library it was made in.
    static func forLibrary(_ libraryId: UUID, user userId: UUID) throws -> PendingChangesFile {
        PendingChangesFile(fileURL: try LocalBookFiles.userFolder(userId)
            .appendingPathComponent("pending-\(libraryId.uuidString.lowercased()).json"))
    }

    /// Loads the saved changes. Entries that can't be decoded (e.g. written by an older version of
    /// the app) are skipped; if the file can't be read at all it's kept as a backup, not overwritten.
    func load() -> [LibraryChange] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let entries = try? JSONDecoder().decode([LossyChange].self, from: data) else {
            let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return []
        }
        return entries.compactMap(\.change)
    }

    private struct LossyChange: Decodable {
        let change: LibraryChange?
        init(from decoder: Decoder) throws {
            change = try? LibraryChange(from: decoder)
        }
    }

    func save(_ changes: [LibraryChange]) {
        if changes.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            try? JSONEncoder().encode(changes).write(to: fileURL, options: .atomic)
        }
    }
}
