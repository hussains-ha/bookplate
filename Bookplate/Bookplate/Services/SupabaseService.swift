import Foundation
import Supabase

/// Connection details for the Supabase project, read from Info.plist.
/// The values come from `Config.xcconfig` (URL) and `Secrets.xcconfig` (key).
struct SupabaseConfig: Equatable {
    let url: URL
    let key: String

    enum ConfigError: Error, Equatable, CustomStringConvertible {
        case missing(String)
        case invalidURL(String)

        var description: String {
            switch self {
            case .missing(let key):
                "\(key) is not set. Copy Bookplate/Secrets.example.xcconfig to Bookplate/Secrets.xcconfig and fill it in."
            case .invalidURL(let value):
                "SupabaseURL \"\(value)\" is not a valid URL."
            }
        }
    }

    init(url: URL, key: String) {
        self.url = url
        self.key = key
    }

    /// Reads `SupabaseURL` and `SupabaseKey` from an Info.plist dictionary.
    init(info: [String: Any]) throws(ConfigError) {
        let urlString = Self.value("SupabaseURL", in: info)
        guard let urlString else { throw .missing("SupabaseURL") }
        guard let url = URL(string: urlString), url.scheme == "https", url.host() != nil else {
            throw .invalidURL(urlString)
        }
        guard let key = Self.value("SupabaseKey", in: info) else { throw .missing("SupabaseKey") }
        self.init(url: url, key: key)
    }

    /// A value is missing when absent, blank, or an unexpanded build setting like `$(SUPABASE_KEY)`.
    private static func value(_ name: String, in info: [String: Any]) -> String? {
        guard let raw = info[name] as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }
}

enum SupabaseService {
    /// The app-wide client, created on first use. Crashes with setup instructions
    /// if the config is missing, rather than failing later with a vague network error.
    static let client: SupabaseClient = {
        do {
            let config = try SupabaseConfig(info: Bundle.main.infoDictionary ?? [:])
            return SupabaseClient(supabaseURL: config.url, supabaseKey: config.key)
        } catch {
            fatalError("Supabase is not configured: \(error)")
        }
    }()
}
