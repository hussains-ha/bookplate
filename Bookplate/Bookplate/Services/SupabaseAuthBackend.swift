import Foundation
import Supabase

/// `AuthBackend` backed by Supabase Auth. Sessions are stored in the Keychain by the SDK.
struct SupabaseAuthBackend: AuthBackend {
    var auth: AuthClient = SupabaseService.client.auth

    func accountChanges() -> AsyncStream<AuthUser?> {
        let changes = auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (_, session) in changes {
                    continuation.yield(session.map { AuthUser($0.user) })
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signUp(name: String, email: String, password: String) async throws {
        do {
            let response = try await auth.signUp(email: email, password: password, data: ["name": .string(name)])
            // With "Confirm email" off in the dashboard, sign-up returns a session right away.
            if case .user = response { throw AuthFailure.confirmationRequired }
        } catch let error as AuthError {
            throw Self.failure(from: error)
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            _ = try await auth.signIn(email: email, password: password)
        } catch let error as AuthError {
            throw Self.failure(from: error)
        }
    }

    func signOut() async throws {
        try await auth.signOut()
    }

    static func failure(from error: AuthError) -> AuthFailure {
        if case .weakPassword(let message, _) = error { return .weakPassword(message) }
        switch error.errorCode {
        case .invalidCredentials: return .invalidCredentials
        case .emailExists, .userAlreadyExists: return .emailTaken
        case .weakPassword: return .weakPassword(error.message)
        case .emailNotConfirmed: return .confirmationRequired
        default: return .other(error.message)
        }
    }
}

private extension AuthUser {
    init(_ user: User) {
        let name: String? = if case .string(let name) = user.userMetadata["name"] { name } else { nil }
        self.init(id: user.id, email: user.email, name: name)
    }
}
