import SwiftUI
import Testing
@testable import Bookplate

struct BookAppearanceTests {
    private func book(id: String, title: String, authors: [String]) -> Book {
        Book(id: id, title: title, authors: authors, pageCount: nil, coverUrl: nil, isbn13: nil)
    }

    private func sameLook(_ a: BookAppearance, _ b: BookAppearance) -> Bool {
        a.color == b.color && a.spineHeight == b.spineHeight && a.coverLayout == b.coverLayout
    }

    @Test func seededByTitleAndAuthorNotId() {
        let first = BookAppearance(book: book(id: "book-1", title: "Dune", authors: ["Frank Herbert"]))
        let readded = BookAppearance(book: book(id: "book-2", title: "Dune", authors: ["Frank Herbert"]))
        #expect(sameLook(first, readded))
    }

    @Test func caseSpacingAndParenthesesDoNotChangeTheLook() {
        let plain = BookAppearance(title: "Dune", author: "Frank Herbert")
        #expect(sameLook(plain, BookAppearance(title: "  DUNE ", author: "frank  herbert")))
        #expect(sameLook(plain, BookAppearance(title: "Dune (Dune Chronicles, #1)", author: "Frank Herbert")))
    }

    @Test func onlyFirstAuthorCounts() {
        let one = BookAppearance(book: book(id: "a", title: "Good Omens", authors: ["Terry Pratchett"]))
        let two = BookAppearance(book: book(id: "b", title: "Good Omens", authors: ["Terry Pratchett", "Neil Gaiman"]))
        #expect(sameLook(one, two))
    }

    @Test func seedIsAFixedValueAcrossLaunches() {
        // Pinned: a changed seed function would silently restyle every user's library.
        #expect(BookAppearance.seed(title: "Dune", author: "Frank Herbert")
            == BookAppearance.seed(title: "dune", author: "frank herbert"))
        #expect(BookAppearance.seed(title: "Dune", author: nil) == BookAppearance.seed(title: "Dune", author: ""))
        #expect(BookAppearance.seed(title: "Dune", author: "Frank Herbert") >= 0)
    }

    @Test func differentBooksUseAllLayoutsAndColors() {
        let looks = (0..<400).map { BookAppearance(title: "Book \($0)", author: "Author \($0 % 7)") }
        #expect(Set(looks.map(\.coverLayout)).count == BookAppearance.CoverLayout.allCases.count)
        #expect(Set(looks.map(\.spineHeight)).count == 5)
        #expect(looks.allSatisfy { (92...116).contains($0.spineHeight) })
    }

    @Test func displayTitleStripsParentheses() {
        #expect(BookAppearance.displayTitle("Dune (Dune Chronicles, #1)") == "Dune")
        #expect(BookAppearance.displayTitle("The Hobbit (Illustrated) (Deluxe)") == "The Hobbit")
        #expect(BookAppearance.displayTitle("Sapiens: A Brief History") == "Sapiens: A Brief History")
        #expect(BookAppearance.displayTitle("(Untitled)") == "(Untitled)")
        #expect(BookAppearance.displayTitle("  Educated  ") == "Educated")
    }

    @Test func layoutsAreTheEightFromTheIssue() {
        #expect(BookAppearance.CoverLayout.allCases.map { String(describing: $0) }
            == ["centered", "top", "bottom", "split", "minimal", "bold", "classic", "stripe"])
    }
}
