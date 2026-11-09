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

    private(set) var status: Status = .idle
    private(set) var pending: [LibraryChange] = [] {
        didSet { pendingFile?.save(pending) }
    }

    let repository: LibraryRepository
    private let pendingFile: PendingChangesFile?
    private let retryDelays: [Duration]
    private let sleep: (Duration) async throws -> Void
    private var worker: Task<Void, Never>?
    private var retryWait: Task<Void, Never>?

    init(repository: LibraryRepository,
         pendingFile: PendingChangesFile? = nil,
         retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30)],
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.repository = repository
        self.pendingFile = pendingFile
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    func enqueue(_ change: LibraryChange) {
        enqueue(contentsOf: [change])
    }

    func enqueue(contentsOf changes: [LibraryChange]) {
        guard !changes.isEmpty else { return }
        pending.append(contentsOf: changes)
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    /// Skips the current backoff wait.
    func retryNow() {
        retryWait?.cancel()
    }

    /// Clears a "rejected" notice.
    func dismissRejection() {
        if case .rejected = status { status = pending.isEmpty ? .idle : .saving }
    }

    /// Waits until every queued change has been saved or dropped. For tests.
    func waitUntilIdle() async {
        while let worker { await worker.value }
    }

    private func drain() async {
        var failures = 0
        while let change = pending.first {
            if case .rejected = status {} else { status = .saving }
            do {
                try await repository.apply(change)
                pending.removeFirst()
                failures = 0
                if case .retrying = status { status = .saving }
            } catch .rejected(let message) {
                pending.removeFirst()
                status = .rejected("Couldn't save a change: \(message)")
            } catch {
                status = .retrying(error.localizedDescription)
                let delay = retryDelays[min(failures, retryDelays.count - 1)]
                failures += 1
                let wait = Task { [sleep] in _ = try? await sleep(delay) }
                retryWait = wait
                await wait.value
                retryWait = nil
            }
        }
        if status == .saving { status = .idle }
        worker = nil
    }
}

/// Changes not yet confirmed by the server, saved per user so they survive quitting the app.
struct PendingChangesFile {
    let fileURL: URL

    static func forUser(_ userId: UUID) throws -> PendingChangesFile {
        PendingChangesFile(fileURL: try LocalBookFiles.userFolder(userId).appendingPathComponent("pending-changes.json"))
    }

    func load() -> [LibraryChange] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([LibraryChange].self, from: data)) ?? []
    }

    func save(_ changes: [LibraryChange]) {
        if changes.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            try? JSONEncoder().encode(changes).write(to: fileURL, options: .atomic)
        }
    }
}
