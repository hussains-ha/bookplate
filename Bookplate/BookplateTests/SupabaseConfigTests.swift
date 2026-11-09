import Foundation
import Testing
@testable import Bookplate

struct SupabaseConfigTests {
    private let url = "https://example.supabase.co"

    @Test func readsURLAndKey() throws {
        let config = try SupabaseConfig(info: ["SupabaseURL": url, "SupabaseKey": "sb_publishable_abc"])
        #expect(config == SupabaseConfig(url: URL(string: url)!, key: "sb_publishable_abc"))
    }

    @Test func missingKeyThrows() {
        #expect(throws: SupabaseConfig.ConfigError.missing("SupabaseKey")) {
            try SupabaseConfig(info: ["SupabaseURL": url])
        }
    }

    @Test(arguments: ["", "  ", "$(SUPABASE_KEY)"])
    func blankOrUnexpandedKeyThrows(key: String) {
        #expect(throws: SupabaseConfig.ConfigError.missing("SupabaseKey")) {
            try SupabaseConfig(info: ["SupabaseURL": url, "SupabaseKey": key])
        }
    }

    @Test func missingURLThrows() {
        #expect(throws: SupabaseConfig.ConfigError.missing("SupabaseURL")) {
            try SupabaseConfig(info: ["SupabaseKey": "k"])
        }
    }

    @Test(arguments: ["not a url", "http://example.supabase.co", "https://"])
    func invalidURLThrows(value: String) {
        #expect(throws: SupabaseConfig.ConfigError.invalidURL(value)) {
            try SupabaseConfig(info: ["SupabaseURL": value, "SupabaseKey": "k"])
        }
    }

    /// The app bundle carries the URL from Config.xcconfig.
    @Test func appBundleHasProjectURL() {
        let value = Bundle.main.infoDictionary?["SupabaseURL"] as? String
        #expect(value == "https://nrbkimnymqctyxnpdzlb.supabase.co")
    }
}
