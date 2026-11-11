import Foundation
#if os(iOS)
import UIKit
#endif

/// Opens the Kindle app. Only the app opens; Kindle has no public link to a specific book.
enum KindleLink {
    static let url = URL(string: "kindle://")!

    /// True when an app handles `kindle://`. Needs `kindle` in `LSApplicationQueriesSchemes`.
    /// `canOpen` is swappable for tests.
    @MainActor
    static func isInstalled(canOpen: (URL) -> Bool = systemCanOpen) -> Bool {
        canOpen(url)
    }

    @MainActor
    static func systemCanOpen(_ url: URL) -> Bool {
        #if os(iOS)
        UIApplication.shared.canOpenURL(url)
        #else
        false
        #endif
    }
}
