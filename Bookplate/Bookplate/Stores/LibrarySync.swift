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

    private(set) var status: Status = .idle
    private(set) var pending: [LibraryChange] = []

    private let repository: LibraryRepository
    private let retryDelays: [Duration]
    private let sleep: (Duration) async throws -> Void
    private var worker: Task<Void, Never>?
    private var retryWait: Task<Void, Never>?

    init(repository: LibraryRepository,
         retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30)],
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.repository = repository
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    func enqueue(_ change: LibraryChange) {
        pending.append(change)
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
