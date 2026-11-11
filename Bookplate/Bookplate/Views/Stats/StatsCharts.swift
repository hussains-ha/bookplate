import Charts
import SwiftUI

/// A titled card on the Stats tab.
struct StatsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.brown)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.mutedText.opacity(0.2)))
    }
}

/// Books finished each month of the year, with the count above each bar.
struct MonthlyChart: View {
    let insights: LibraryInsights

    var body: some View {
        let total = insights.finishedPerMonth.reduce(0) { $0 + $1.count }
        StatsCard(title: "Books finished", subtitle: "\(total) in \(String(insights.year))") {
            Chart(insights.finishedPerMonth) { item in
                BarMark(x: .value("Month", Self.monthLabel(item.month)), y: .value("Books", item.count))
                    .foregroundStyle(Theme.brown.gradient)
                    .cornerRadius(3)
                    .annotation(position: .top, spacing: 2) {
                        if item.count > 0 {
                            Text("\(item.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.brown)
                        }
                    }
                    .accessibilityLabel(Self.monthName(item.month))
                    .accessibilityValue(item.count == 1 ? "1 book" : "\(item.count) books")
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...max(insights.finishedPerMonth.map(\.count).max() ?? 0, 1) + 1)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.caption2).foregroundStyle(Theme.mutedText)
                }
            }
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Books finished each month")
            .accessibilityValue(summary)
        }
    }

    private var summary: String {
        let months = insights.finishedPerMonth.filter { $0.count > 0 }
        guard !months.isEmpty else { return "None yet" }
        return months.map { "\(Self.monthName($0.month)): \($0.count)" }.joined(separator: ", ")
    }

    static func monthLabel(_ month: Int) -> String {
        // Short names are unique per month, so each is its own bar (one-letter names repeat).
        Calendar.current.shortMonthSymbols[month - 1]
    }

    static func monthName(_ month: Int) -> String { Calendar.current.monthSymbols[month - 1] }
}

/// The latest finished books with their finish date and rating.
struct RecentReadsCard: View {
    let reads: [LibraryInsights.RecentRead]
    let onSelect: (Book) -> Void

    var body: some View {
        StatsCard(title: "Recent reads", subtitle: reads.isEmpty ? nil : "Latest \(reads.count)") {
            if reads.isEmpty {
                Text("Books you mark Read show up here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.mutedText)
            } else {
                VStack(spacing: 0) {
                    ForEach(reads) { read in
                        Button { onSelect(read.book) } label: { row(read) }
                            .buttonStyle(.plain)
                        if read.id != reads.last?.id { Divider().overlay(Theme.mutedText.opacity(0.2)) }
                    }
                }
            }
        }
    }

    private func row(_ read: LibraryInsights.RecentRead) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(read.book.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.brown)
                    .lineLimit(1)
                Text(read.finished.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)
            }
            Spacer(minLength: 8)
            if let rating = read.rating {
                Text(String(repeating: "★", count: rating))
                    .font(.caption)
                    .foregroundStyle(Theme.statusWant)
                    .accessibilityLabel("\(rating) stars")
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// How many books have each star rating, 5 stars first.
struct RatingChart: View {
    let distribution: [LibraryInsights.RatingCount]

    var body: some View {
        let rated = distribution.reduce(0) { $0 + $1.count }
        let most = Double(max(distribution.map(\.count).max() ?? 0, 1))
        StatsCard(title: "Ratings", subtitle: "\(rated) rated") {
            VStack(spacing: 8) {
                ForEach(distribution.reversed()) { item in
                    HStack(spacing: 10) {
                        Text("\(item.stars) ★")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.mutedText)
                            .frame(width: 30, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule().fill(Theme.statusWant.opacity(0.15))
                                .overlay(alignment: .leading) {
                                    if item.count > 0 {
                                        Capsule().fill(Theme.statusWant)
                                            .frame(width: max(proxy.size.width * Double(item.count) / most, 6))
                                    }
                                }
                        }
                        .frame(height: 10)
                        Text("\(item.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.brown)
                            .frame(width: 26, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.stars == 1 ? "1 star" : "\(item.stars) stars")
                    .accessibilityValue(item.count == 1 ? "1 book" : "\(item.count) books")
                }
            }
        }
    }
}

/// A ranked list with a bar per name, for authors and tags.
struct RankedCard: View {
    let title: String
    let items: [LibraryInsights.NameCount]
    let empty: String
    var showsPercent = false
    var prefix = ""

    var body: some View {
        StatsCard(title: title) {
            if items.isEmpty {
                Text(empty).font(.footnote).foregroundStyle(Theme.mutedText)
            } else {
                let most = Double(items.map(\.count).max() ?? 1)
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(prefix + item.name)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.brown)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(label(item))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.mutedText)
                            }
                            GeometryReader { proxy in
                                Capsule().fill(Theme.brown.opacity(0.12))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Theme.brown.opacity(0.7))
                                            .frame(width: max(proxy.size.width * Double(item.count) / most, 6))
                                    }
                            }
                            .frame(height: 6)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(prefix + item.name)
                        .accessibilityValue(label(item))
                    }
                }
            }
        }
    }

    private func label(_ item: LibraryInsights.NameCount) -> String {
        let books = item.count == 1 ? "1 book" : "\(item.count) books"
        guard showsPercent else { return books }
        return "\(books) · \(item.fraction.formatted(.percent.precision(.fractionLength(0))))"
    }
}

/// Totals from books with a page count.
struct PagesCard: View {
    let pages: LibraryInsights.PageTotals?

    var body: some View {
        StatsCard(title: "Pages", subtitle: pages.map { "From \($0.books) \($0.books == 1 ? "book" : "books") with a page count" }) {
            if let pages {
                HStack(spacing: 10) {
                    figure(pages.total.formatted(), "Total")
                    figure(pages.average.formatted(), "Average")
                }
                book("Longest", pages.longest)
                book("Shortest", pages.shortest)
            } else {
                Text("No books have a page count yet.").font(.footnote).foregroundStyle(Theme.mutedText)
            }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.title(22)).foregroundStyle(Theme.brown).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(Theme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func book(_ label: String, _ book: Book) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundStyle(Theme.mutedText)
            Spacer(minLength: 8)
            Text(book.title).font(.footnote.weight(.medium)).foregroundStyle(Theme.brown).lineLimit(1)
            Text("\(book.pageCount ?? 0) p.").font(.footnote.monospacedDigit()).foregroundStyle(Theme.mutedText)
        }
        .accessibilityElement(children: .combine)
    }
}
