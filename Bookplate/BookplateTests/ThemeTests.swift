import Foundation
import SwiftUI
import Testing
@testable import Bookplate
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct ThemeTests {
    @Test(arguments: Bookshelf.Appearance.allCases)
    func everyAppearanceHasItsOwnCompletePalette(_ appearance: Bookshelf.Appearance) {
        let palette = Palette.of(appearance)
        let others = Bookshelf.Appearance.allCases.filter { $0 != appearance }.map(Palette.of)
        #expect(!others.contains(palette))
        #expect(!appearance.title.isEmpty)
    }

    @Test func classicMatchesTheOriginalColors() {
        #expect(Palette.classic.frame == Theme.wood)
        #expect(Palette.classic.shelf == Theme.woodShelf)
        #expect(Palette.classic.plate == Theme.label)
        #expect(Palette.classic.accent == Theme.brown)
    }

    #if canImport(UIKit)
    /// WCAG contrast ratio between two colors.
    private func contrast(_ a: Color, _ b: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, alpha: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &bl, alpha: &alpha)
            func linear(_ c: CGFloat) -> Double {
                let c = Double(c)
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(bl)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    @Test(arguments: Bookshelf.Appearance.allCases)
    func textIsReadable(_ appearance: Bookshelf.Appearance) {
        let p = Palette.of(appearance)
        #expect(contrast(p.plateText, p.plate) >= 4.5)
        #expect(contrast(p.shelfText, p.shelf) >= 4.5)
        #expect(contrast(p.accent, p.background) >= 4.5)
        #expect(contrast(p.mutedText, p.background) >= 3)
    }

    @Test(arguments: Bookshelf.Appearance.allCases)
    func searchFieldAndSpinesFitTheTheme(_ appearance: Bookshelf.Appearance) {
        let p = Palette.of(appearance)
        // Typed text and the placeholder stay readable on the themed field.
        #expect(contrast(p.accent, p.field) >= 4.5)
        #expect(contrast(p.mutedText, p.field) >= 3)
        #expect(p.spineOutline != .clear)
    }

    @Test func searchFieldIsThemedPerAppearance() {
        #expect(Palette.modern.field != Palette.classic.field)
        #expect(Palette.maple.field != Palette.classic.field)
    }
    #endif

    @Test func setAppearanceUpdatesTheBookcaseAndSaves() async throws {
        let repo = InMemoryLibraryRepository()
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        #expect(store.bookshelf.appearance == .classic)
        store.setAppearance(.maple)
        store.setAppearance(.maple)
        #expect(store.bookshelf.appearance == .maple)
        await sync.waitUntilIdle()
        #expect(repo.applied == [.saveSettings(LibrarySettings(readingGoal: 24, appearance: .maple))])
        let reloaded = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                           localFiles: nil, coverLookup: NoCoverLookup())
        #expect(reloaded.bookshelf.appearance == .maple)
    }

    @Test func settingsRowRoundTripsAndFallsBack() throws {
        let row = SettingsRow(LibrarySettings(readingGoal: 5, appearance: .modern))
        #expect(row.appearance == "modern")
        #expect(row.settings == LibrarySettings(readingGoal: 5, appearance: .modern))
        let unknown = try JSONDecoder().decode(SettingsRow.self,
                                               from: Data(#"{"reading_goal":3,"appearance":"neon"}"#.utf8))
        #expect(unknown.settings.appearance == .classic)
    }
}
