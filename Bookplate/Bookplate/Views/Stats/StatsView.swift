import SwiftUI

/// The Stats tab: this year's reading goal and library totals.
struct StatsView: View {
    @Environment(LibraryStore.self) private var store
    @State private var showingGoalEditor = false

    var body: some View {
        let stats = store.stats
        let progress = store.readingGoalProgress()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GoalCard(progress: progress) { showingGoalEditor = true }
                    Text("Overview")
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.brown)
                        .padding(.top, 4)
                    overview(stats)
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Stats")
        }
        .tint(Theme.brown)
        .sheet(isPresented: $showingGoalEditor) {
            GoalEditor(year: progress.year, goal: store.settings.readingGoal) { store.setReadingGoal($0) }
        }
    }

    private func overview(_ stats: LibraryStats) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 10) {
                StatTile(value: "\(stats.totalBooks)", label: "Books")
                StatTile(value: "\(stats.totalAuthors)", label: "Authors")
                StatTile(value: "\(stats.totalShelves)", label: "Shelves")
                StatTile(value: "\(stats.readCount)", label: "Read", dot: Theme.statusRead)
                StatTile(value: "\(stats.readingCount)", label: "Reading", dot: Theme.statusReading)
                StatTile(value: "\(stats.ratedCount)", label: "Rated")
            }
            StatTile(value: stats.averageRating.map { String(format: "%.1f ★", $0) } ?? "—",
                     label: "Average rating")
        }
    }
}

private struct GoalCard: View {
    let progress: ReadingGoalProgress
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.brown.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(Theme.statusRead, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(progress.finished)")
                        .font(Theme.title(26))
                    Text("of \(progress.goal)")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedText)
                }
            }
            .frame(width: 96, height: 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(progress.finished) of \(progress.goal) books read")

            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(progress.year) reading goal")
                    .font(Theme.title(18))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Change goal", action: onEdit)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.brown)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.brown)
        .padding(16)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.mutedText.opacity(0.2)))
    }

    private var detail: String {
        if progress.isComplete { return "Goal reached. Nice reading!" }
        let books = progress.remaining == 1 ? "book" : "books"
        // Whole books, rounded up so keeping pace reaches the goal.
        let pace = String(Int(progress.perMonth.rounded(.up)))
        let months = progress.monthsLeft == 1 ? "this month" : "a month for \(progress.monthsLeft) months"
        return "\(progress.remaining) \(books) to go: about \(pace) \(months)."
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    var dot: Color?

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.title(24))
                .foregroundStyle(Theme.brown)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.mutedText.opacity(0.2)))
        .accessibilityElement(children: .combine)
    }
}

private struct GoalEditor: View {
    let year: Int
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var goal: Int

    init(year: Int, goal: Int, onSave: @escaping (Int) -> Void) {
        self.year = year
        self.onSave = onSave
        _goal = State(initialValue: goal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $goal, in: LibrarySettings.readingGoalRange) {
                        Text("\(goal) books")
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                } footer: {
                    Text(verbatim: "Books to finish in \(year). Books count when you mark them Read.")
                }
            }
            .navigationTitle("Reading Goal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(goal)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(240)])
        .presentationBackground(Theme.background)
    }
}

#Preview {
    StatsView()
        .environment(LibraryStore.sample())
}
