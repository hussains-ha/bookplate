import Foundation
import Testing
@testable import Bookplate

@MainActor
struct BookplateDesignTests {
    @Test func sixStylesThreeSizesSixFonts() {
        #expect(BookplateDesign.Style.allCases.map(\.title) == ["Classic", "Formal", "Modern", "Script", "Stamp", "Minimal"])
        #expect(BookplateDesign.Size.allCases.map(\.title) == ["Small", "Medium", "Large"])
        #expect(BookplateDesign.LabelFont.allCases.count == 6)
        #expect(BookplateDesign.labelSizes == 9...14)
    }

    @Test func blankPhraseUsesTheStyleDefault() {
        var design = BookplateDesign(style: .formal)
        #expect(design.displayPhrase == "Ex Libris")
        design.phrase = "   "
        #expect(design.displayPhrase == "Ex Libris")
        design.phrase = " Books of the Reed family "
        #expect(design.displayPhrase == "Books of the Reed family")
        #expect(Set(BookplateDesign.Style.allCases.map(\.defaultPhrase)).count == 6)
    }

    @Test func cleanedKeepsLimits() {
        let design = BookplateDesign(phrase: String(repeating: "x", count: 60), labelSize: 30).cleaned
        #expect(design.phrase.count == BookplateDesign.maxPhraseLength)
        #expect(design.labelSize == 14)
        #expect(BookplateDesign(labelSize: 2).cleaned.labelSize == 9)
    }

    @Test func decodesWithDefaultsForMissingOrUnknownValues() throws {
        let empty = try JSONDecoder().decode(BookplateDesign.self, from: Data("{}".utf8))
        #expect(empty == BookplateDesign())
        let json = #"{"style":"stamp","size":"huge","phrase":"Mine","label_font":"didot","label_size":40}"#
        let design = try JSONDecoder().decode(BookplateDesign.self, from: Data(json.utf8))
        #expect(design == BookplateDesign(style: .stamp, size: .medium, phrase: "Mine", labelFont: .didot, labelSize: 14))
    }

    @Test func encodesSnakeCaseKeysAndRoundTrips() throws {
        let design = BookplateDesign(style: .script, size: .large, phrase: "Hi", labelFont: .typewriter, labelSize: 12)
        let data = try JSONEncoder().encode(design)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["label_font"] as? String == "typewriter")
        #expect(object["label_size"] as? Int == 12)
        #expect(try JSONDecoder().decode(BookplateDesign.self, from: data) == design)
    }

    @Test func settingsRowWithoutBookplateUsesDefaults() throws {
        let row = try JSONDecoder().decode(SettingsRow.self, from: Data(#"{"reading_goal":5}"#.utf8))
        #expect(row.settings.bookplate == BookplateDesign())
    }

    @Test func setBookplateSavesCleanedDesignAndLoadsIt() async throws {
        let repo = InMemoryLibraryRepository()
        let sync = LibrarySync(repository: repo, pendingFile: nil, retryDelays: [.zero], sleep: { _ in })
        let store = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                        localFiles: nil, coverLookup: NoCoverLookup())
        store.setBookplate(BookplateDesign(style: .formal, size: .small, labelFont: .serif, labelSize: 99))
        store.setBookplate(BookplateDesign(style: .formal, size: .small, labelFont: .serif, labelSize: 14))
        await sync.waitUntilIdle()
        let expected = BookplateDesign(style: .formal, size: .small, labelFont: .serif, labelSize: 14)
        #expect(store.settings.bookplate == expected)
        #expect(repo.applied.count == 1)
        let reloaded = LibraryStore.loaded(try await repo.loadLibrary(), userId: UUID(), sync: sync,
                                           localFiles: nil, coverLookup: NoCoverLookup())
        #expect(reloaded.settings.bookplate == expected)
    }
}
