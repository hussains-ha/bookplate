import Foundation
import Testing
@testable import Bookplate

struct LibraryCSVTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func book(_ id: String, _ title: String, _ authors: [String] = ["A"]) -> Book {
        Book(id: id, title: title, authors: authors, pageCount: nil, coverUrl: nil, isbn13: nil)
    }

    private func meta(_ id: String, status: String = BookMeta.Status.want, rating: Int? = nil, notes: String? = nil,
                      tags: [String] = [], started: Date? = nil, finished: Date? = nil) -> BookMeta {
        BookMeta(bookId: id, status: status, rating: rating, notes: notes, notePhotos: [], tags: tags,
                 customCover: nil, addedDate: Date(), startedDate: started, finishedDate: finished)
    }

    private func lines(_ csv: String) -> [String] {
        Array(csv.components(separatedBy: "\r\n").dropLast(1))
    }

    @Test func headerHasTheColumnsInOrder() {
        let csv = LibraryCSV.make(books: [], metas: [], shelves: [], calendar: calendar)
        #expect(csv == "Shelf,Title,Full Title,Author,Status,Started,Finished,Rating,Notes,Tags\r\n")
    }

    @Test func rowHasEveryField() {
        let books = [book("1", "Dune (Dune Chronicles, #1)", ["Frank Herbert"])]
        let metas = [meta("1", status: BookMeta.Status.read, rating: 5, notes: "Great", tags: ["sci-fi", "classic"],
                          started: date(2026, 1, 2), finished: date(2026, 2, 3))]
        let shelves = [Shelf(id: "s", name: "Fiction", bookIds: ["1"])]
        let rows = lines(LibraryCSV.make(books: books, metas: metas, shelves: shelves, calendar: calendar))
        #expect(rows[1] == "Fiction,Dune,\"Dune (Dune Chronicles, #1)\",Frank Herbert,Read,2026-01-02,2026-02-03,5,Great,sci-fi; classic")
    }

    @Test func emptyFieldsStayEmpty() {
        let rows = lines(LibraryCSV.make(books: [book("1", "X")], metas: [meta("1")],
                                         shelves: [Shelf(id: "s", name: "S", bookIds: ["1"])], calendar: calendar))
        #expect(rows[1] == "S,X,X,A,Want to Read,,,,,")
    }

    @Test func followsBookcaseOrderAndIncludesBooksOnNoShelf() {
        let books = [book("1", "One"), book("2", "Two"), book("3", "Three")]
        let shelves = [Shelf(id: "a", name: "A", bookIds: ["2"]), Shelf(id: "b", name: "B", bookIds: ["1", "gone"])]
        let rows = lines(LibraryCSV.make(books: books, metas: [], shelves: shelves, calendar: calendar))
        #expect(rows.dropFirst().map { $0.components(separatedBy: ",").prefix(2).joined(separator: ",") }
                == ["A,Two", "B,One", ",Three"])
    }

    @Test func escapesCommasQuotesAndLineBreaks() {
        #expect(LibraryCSV.escape("plain") == "plain")
        #expect(LibraryCSV.escape("a, b") == "\"a, b\"")
        #expect(LibraryCSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(LibraryCSV.escape("line\nbreak") == "\"line\nbreak\"")
        #expect(LibraryCSV.escape("cr\r\nlf") == "\"cr\r\nlf\"")
        #expect(LibraryCSV.escape("") == "")
    }

    @Test func notesWithLineBreaksStayInOneField() {
        let csv = LibraryCSV.make(books: [book("1", "X", ["Last, First"])],
                                  metas: [meta("1", notes: "Line 1\nShe said \"wow\"")],
                                  shelves: [], calendar: calendar)
        #expect(csv.hasSuffix(",X,X,\"Last, First\",Want to Read,,,,\"Line 1\nShe said \"\"wow\"\"\",\r\n"))
    }

    @Test func customStatusPassesThrough() {
        #expect(LibraryCSV.statusLabel("abandoned") == "abandoned")
        #expect(LibraryCSV.statusLabel(BookMeta.Status.reading) == "Reading")
    }

    @Test func fileDataStartsWithAByteOrderMark() {
        let data = LibraryCSV.data("é")
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: data.dropFirst(3), as: UTF8.self) == "é")
    }

    @Test func fileNameHasTheDate() {
        #expect(LibraryCSV.fileName(now: date(2026, 11, 10), calendar: calendar) == "Bookplate Library 2026-11-10.csv")
    }
}
