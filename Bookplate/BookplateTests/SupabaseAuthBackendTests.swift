import Foundation
import Supabase
import Testing
@testable import Bookplate

struct SupabaseAuthBackendTests {
    private func apiError(_ code: ErrorCode, message: String = "server message") -> AuthError {
        .api(message: message, errorCode: code, underlyingData: Data(),
             underlyingResponse: HTTPURLResponse(url: URL(string: "https://example.com")!,
                                                 statusCode: 400, httpVersion: nil, headerFields: nil)!)
    }

    @Test func mapsKnownErrorCodes() {
        #expect(SupabaseAuthBackend.failure(from: apiError(.invalidCredentials)) == .invalidCredentials)
        #expect(SupabaseAuthBackend.failure(from: apiError(.userAlreadyExists)) == .emailTaken)
        #expect(SupabaseAuthBackend.failure(from: apiError(.emailExists)) == .emailTaken)
        #expect(SupabaseAuthBackend.failure(from: apiError(.emailNotConfirmed)) == .confirmationRequired)
    }

    @Test func weakPasswordKeepsServerMessage() {
        let error = AuthError.weakPassword(message: "Password is too weak", reasons: ["length"])
        #expect(SupabaseAuthBackend.failure(from: error) == .weakPassword("Password is too weak"))
    }

    @Test func unknownCodesKeepServerMessage() {
        #expect(SupabaseAuthBackend.failure(from: apiError(ErrorCode("something_new"), message: "Try later"))
                == .other("Try later"))
    }
}
