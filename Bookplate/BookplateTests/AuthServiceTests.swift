import Foundation
import Testing
@testable import Bookplate

/// Records calls and lets tests push session changes.
@MainActor
final class FakeAuthBackend: AuthBackend {
    var signInError: Error?
    var signUpError: Error?
    private(set) var signIns: [(email: String, password: String)] = []
    private(set) var signUps: [(name: String, email: String)] = []
    private(set) var signOutCount = 0
    private var continuation: AsyncStream<AuthUser?>.Continuation?

    nonisolated func accountChanges() -> AsyncStream<AuthUser?> {
        let (stream, continuation) = AsyncStream<AuthUser?>.makeStream()
        MainActor.assumeIsolated { self.continuation = continuation }
        return stream
    }

    func emit(_ account: AuthUser?) { continuation?.yield(account) }
    func finish() { continuation?.finish() }

    func signUp(name: String, email: String, password: String) async throws {
        signUps.append((name, email))
        if let signUpError { throw signUpError }
    }

    func signIn(email: String, password: String) async throws {
        signIns.append((email, password))
        if let signInError { throw signInError }
    }

    func signOut() async throws { signOutCount += 1 }
}

@MainActor
struct AuthServiceTests {
    let backend = FakeAuthBackend()
    let reader = AuthUser(id: UUID(), email: "reader@example.com", name: "Reader")

    private func service() -> AuthService { AuthService(backend: backend) }

    /// Runs `observeSession` while `body` emits session changes, then ends the stream.
    private func observing(_ auth: AuthService, _ body: () async -> Void) async {
        let task = Task { await auth.observeSession() }
        await Task.yield()
        await body()
        backend.finish()
        await task.value
    }

    /// Lets the observing task catch up, without depending on exact scheduling.
    private func settle(_ auth: AuthService, to expected: AuthService.State) async {
        for _ in 0..<100 where auth.state != expected { await Task.yield() }
    }

    @Test func startsLoading() {
        #expect(service().state == .loading)
    }

    @Test func followsSessionChanges() async {
        let auth = service()
        await observing(auth) {
            backend.emit(nil)
            await settle(auth, to: .signedOut)
            #expect(auth.state == .signedOut)
            backend.emit(reader)
            await settle(auth, to: .signedIn(reader))
            #expect(auth.state == .signedIn(reader))
            #expect(auth.user == reader)
        }
    }

    @Test func signInTrimsEmailAndCallsBackend() async throws {
        try await service().signIn(email: "  reader@example.com ", password: "secret")
        #expect(backend.signIns.map(\.email) == ["reader@example.com"])
    }

    @Test(arguments: ["", "reader", "reader@", "@example.com", "reader@example", "rea der@example.com"])
    func signInRejectsInvalidEmail(email: String) async {
        await #expect(throws: AuthFailure.invalidEmail) {
            try await service().signIn(email: email, password: "secret")
        }
        #expect(backend.signIns.isEmpty)
    }

    @Test func signInPassesBackendFailureThrough() async {
        backend.signInError = AuthFailure.invalidCredentials
        await #expect(throws: AuthFailure.invalidCredentials) {
            try await service().signIn(email: "reader@example.com", password: "wrong")
        }
    }

    @Test func networkErrorsBecomeNetworkFailure() async {
        backend.signInError = URLError(.notConnectedToInternet)
        await #expect(throws: AuthFailure.network) {
            try await service().signIn(email: "reader@example.com", password: "secret")
        }
    }

    @Test func signUpSendsTrimmedNameAndEmail() async throws {
        try await service().signUp(name: " Reader ", email: "reader@example.com",
                                   password: "secret1", confirmPassword: "secret1")
        #expect(backend.signUps.map(\.name) == ["Reader"])
        #expect(backend.signUps.map(\.email) == ["reader@example.com"])
    }

    @Test func signUpValidatesBeforeCallingBackend() async {
        let auth = service()
        await #expect(throws: AuthFailure.missingName) {
            try await auth.signUp(name: " ", email: "reader@example.com", password: "secret1", confirmPassword: "secret1")
        }
        await #expect(throws: AuthFailure.invalidEmail) {
            try await auth.signUp(name: "Reader", email: "reader", password: "secret1", confirmPassword: "secret1")
        }
        await #expect(throws: AuthFailure.passwordTooShort(minimum: 6)) {
            try await auth.signUp(name: "Reader", email: "reader@example.com", password: "abc", confirmPassword: "abc")
        }
        await #expect(throws: AuthFailure.passwordsDontMatch) {
            try await auth.signUp(name: "Reader", email: "reader@example.com", password: "secret1", confirmPassword: "secret2")
        }
        #expect(backend.signUps.isEmpty)
    }

    @Test func signOutCallsBackend() async {
        await service().signOut()
        #expect(backend.signOutCount == 1)
    }

    @Test func bypassSkipsBackendAndSignsOutLocally() async {
        let auth = service()
        auth.bypass()
        #expect(auth.state == .bypassed)
        await auth.signOut()
        #expect(auth.state == .signedOut)
        #expect(backend.signOutCount == 0)
    }

    @Test func bypassSurvivesSignedOutSession() async {
        let auth = service()
        auth.bypass()
        await observing(auth) {
            backend.emit(nil)
            await Task.yield()
            #expect(auth.state == .bypassed)
        }
    }

    @Test func signingOutElsewhereReturnsToLogin() async {
        let auth = service()
        await observing(auth) {
            backend.emit(reader)
            await settle(auth, to: .signedIn(reader))
            #expect(auth.state == .signedIn(reader))
            backend.emit(nil)   // sign out, or the SDK revoking an expired session
            await settle(auth, to: .signedOut)
            #expect(auth.state == .signedOut)
            #expect(auth.user == nil)
        }
    }

    @Test func streamEndingWhileLoadingShowsLogin() async {
        let auth = service()
        await observing(auth) {}
        #expect(auth.state == .signedOut)
    }

    @Test func errorMessagesAreUserFacing() {
        #expect(AuthFailure.invalidCredentials.localizedDescription == "Incorrect email or password.")
        #expect(AuthFailure.passwordTooShort(minimum: 6).localizedDescription == "Password must be at least 6 characters.")
    }
}
