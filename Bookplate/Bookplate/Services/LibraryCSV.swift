import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The library as a CSV spreadsheet: one row per book, in bookcase order.
enum LibraryCSV {
    static let columns = ["Shelf", "Title", "Full Title", "Author", "Status", "Started", "Finished",
                          "Rating", "Notes", "Tags"]

    /// RFC 4180: comma separated, CRLF line endings, fields quoted when needed.
    static func make(books: [Book], metas: [BookMeta], shelves: [Shelf], calendar: Calendar = .current) -> String {
        let byId = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let metaById = Dictionary(metas.map { ($0.bookId, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var rows: [(shelf: String, book: Book)] = []
        for shelf in shelves {
            for id in shelf.bookIds where seen.insert(id).inserted {
                if let book = byId[id] { rows.append((shelf.name, book)) }
            }
        }
        // Books on no shelf still export, with an empty shelf.
        for book in books where seen.insert(book.id).inserted { rows.append(("", book)) }

        let lines = [columns] + rows.map { row in
            let meta = metaById[row.book.id]
            return [
                row.shelf,
                BookAppearance.displayTitle(row.book.title),
                row.book.title,
                row.book.authors.joined(separator: ", "),
                meta.map { statusLabel($0.status) } ?? "",
                meta?.startedDate.map { day($0, calendar) } ?? "",
                meta?.finishedDate.map { day($0, calendar) } ?? "",
                meta?.rating.map(String.init) ?? "",
                meta?.notes ?? "",
                meta?.tags.joined(separator: "; ") ?? "",
            ]
        }
        return lines.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field that contains a comma, quote or line break, doubling any quotes.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func statusLabel(_ status: String) -> String {
        switch status {
        case BookMeta.Status.want: "Want to Read"
        case BookMeta.Status.reading: "Reading"
        case BookMeta.Status.read: "Read"
        default: status
        }
    }

    /// `yyyy-MM-dd` in the user's calendar, so spreadsheets read it as a date.
    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// UTF-8 with a byte-order mark, so Excel shows accented text correctly.
    static func data(_ csv: String) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8)
    }

    static func fileName(now: Date = Date(), calendar: Calendar = .current) -> String {
        "Bookplate Library \(day(now, calendar)).csv"
    }
}

/// A CSV export the share sheet writes to a file when the user picks a destination.
struct LibraryCSVFile: Transferable {
    let csv: String
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(file.fileName)
            try LibraryCSV.data(file.csv).write(to: url)
            return SentTransferredFile(url)
        }
    }
}

extension LibraryStore {
    var csvExport: LibraryCSVFile {
        LibraryCSVFile(csv: LibraryCSV.make(books: books, metas: metas, shelves: bookshelf.shelves),
                       fileName: LibraryCSV.fileName())
    }
}
