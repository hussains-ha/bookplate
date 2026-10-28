import Foundation

extension Book {
    /// The one place that decides which cover image a book shows.
    /// Priority: the user's custom cover, then the official cover, then nil (use the generated cover).
    func displayCoverURL(meta: BookMeta?) -> URL? {
        meta?.customCover ?? coverUrl
    }
}
