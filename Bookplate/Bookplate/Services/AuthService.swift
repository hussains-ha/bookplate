import Foundation
import Observation

/// The signed-in account, independent of the Supabase SDK types.
struct AuthUser: Equatable, Sendable {
    let id: UUID
    let email: String?
    /// The name entered at sign-up, saved in the account's metadata.
    let name: String?
}

/// Errors the auth screens can show as-is.
enum AuthFailure: Error, Equatable, LocalizedError {
    case missingName
    case invalidEmail
    case passwordsDontMatch
    case passwordTooShort(minimum: Int)
    case invalidCredentials
    case emailTaken
    case weakPassword(String)
    case confirmationRequired
    case network
    case other(String)

    var errorDescription: String? {
        switch self {
        case .missingName: "Enter your name."
        case .invalidEmail: "Enter a valid email address."
        case .passwordsDontMatch: "Passwords don't match."
        case .passwordTooShort(let minimum): "Password must be at least \(minimum) characters."
        case .invalidCredentials: "Incorrect email or password."
        case .emailTaken: "An account with this email already exists."
        case .weakPassword(let message): message
        case .confirmationRequired: "Check your email to confirm your account, then sign in."
        case .network: "Can't reach Bookplate. Check your connection and try again."
        case .other(let message): message
        }
    }
}

/// The auth calls AuthService needs. `SupabaseAuthBackend` is the real one; tests use a fake.
protocol AuthBackend {
    /// Emits the current account on start, then on every sign-in, sign-out or refresh. `nil` means signed out.
    func accountChanges() -> AsyncStream<AuthUser?>
    func signUp(name: String, email: String, password: String) async throws
    func signIn(email: String, password: String) async throws
    func signOut() async throws
}

@Observable
final class AuthService {
    enum State: Equatable {
        /// Checking the Keychain for a saved session.
        case loading
        case signedOut
        case signedIn(AuthUser)
        /// "Skip to library (dev)": no account, no backend.
        case bypassed
    }

    static let minimumPasswordLength = 6

    private(set) var state: State = .loading
    private let backend: AuthBackend

    init(backend: AuthBackend) {
        self.backend = backend
    }

    var user: AuthUser? {
        if case .signedIn(let user) = state { user } else { nil }
    }

    /// Follows the backend's session for the life of the app. Call once, from a `.task`.
    func observeSession() async {
        for await account in backend.accountChanges() {
            if state == .bypassed && account == nil { continue }
            state = account.map(State.signedIn) ?? .signedOut
        }
    }

    func signIn(email: String, password: String) async throws(AuthFailure) {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else { throw .invalidEmail }
        do {
            try await backend.signIn(email: email, password: password)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func signUp(name: String, email: String, password: String, confirmPassword: String) async throws(AuthFailure) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .missingName }
        guard Self.isValidEmail(email) else { throw .invalidEmail }
        guard password.count >= Self.minimumPasswordLength else {
            throw .passwordTooShort(minimum: Self.minimumPasswordLength)
        }
        guard password == confirmPassword else { throw .passwordsDontMatch }
        do {
            try await backend.signUp(name: name, email: email, password: password)
        } catch {
            throw Self.failure(from: error)
        }
    }

    func signOut() async {
        if state == .bypassed {
            state = .signedOut
            return
        }
        // Even if the server call fails, the SDK clears the local session and emits a sign-out.
        try? await backend.signOut()
    }

    func bypass() {
        state = .bypassed
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !email.contains(" ")
    }

    private static func failure(from error: Error) -> AuthFailure {
        if let failure = error as? AuthFailure { return failure }
        if error is URLError { return .network }
        return .other(error.localizedDescription)
    }
}

#if DEBUG
/// A backend for SwiftUI previews: starts in the given account and never touches the network.
struct PreviewAuthBackend: AuthBackend {
    var account: AuthUser?

    func accountChanges() -> AsyncStream<AuthUser?> {
        AsyncStream { $0.yield(account) }
    }
    func signUp(name: String, email: String, password: String) async throws {}
    func signIn(email: String, password: String) async throws {}
    func signOut() async throws {}
}
#endif
