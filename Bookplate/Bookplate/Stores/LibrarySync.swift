import Foundation
import Observation

/// Saves library changes in order, one at a time. A failed save stays at the front of the
/// queue and is retried with backoff; changes the database refuses are dropped and reported.
// TODO(supabase): the queue lives in memory, so changes not yet saved are lost if the app quits (#11).
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

    private(set) var pending: [LibraryChange] = []
    private var retryMessage: String?
    private var rejection: String?

    private let repository: LibraryRepository
    private let retryDelays: [Duration]
    private let sleep: (Duration) async throws -> Void
    private var worker: Task<Void, Never>?
    private var retryWait: Task<Void, Never>?
    /// The change being sent right now, which must not be replaced while in flight.
    private var sending = false
    private var stopped = false

    init(repository: LibraryRepository,
         retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30)],
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.repository = repository
        self.retryDelays = retryDelays
        self.sleep = sleep
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

    /// Stops saving for good (sign-out or account switch). Unsent changes are discarded here;
    /// #11 keeps them on disk for the next sign-in.
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
        default: false
        }
    }
}
