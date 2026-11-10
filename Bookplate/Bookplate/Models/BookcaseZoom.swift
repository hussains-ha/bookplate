import SwiftUI

/// The bookcase zoom: seven steps from 50% to 145%, 100% by default.
struct BookcaseZoom: Equatable, Sendable {
    static let steps: [CGFloat] = [0.5, 0.65, 0.8, 1, 1.15, 1.3, 1.45]
    static let standard = BookcaseZoom(index: 3)

    private(set) var index: Int

    init(index: Int) {
        self.index = min(max(index, 0), Self.steps.count - 1)
    }

    var scale: CGFloat { Self.steps[index] }
    var percent: Int { Int((scale * 100).rounded()) }
    var canZoomIn: Bool { index < Self.steps.count - 1 }
    var canZoomOut: Bool { index > 0 }

    func zoomedIn() -> BookcaseZoom { BookcaseZoom(index: index + 1) }
    func zoomedOut() -> BookcaseZoom { BookcaseZoom(index: index - 1) }

    /// Spine title size: scales, but never below a readable minimum.
    static func titleSize(at scale: CGFloat) -> CGFloat { max(6, 9 * scale) }
    /// Author size on spines, or nil when the spine is too small to fit it legibly.
    static func authorSize(at scale: CGFloat) -> CGFloat? { scale < 0.8 ? nil : 6.5 * scale }
}

extension EnvironmentValues {
    /// Scale for spines and shelves (1 = 100%).
    @Entry var bookcaseScale: CGFloat = 1
}
