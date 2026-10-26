import SwiftUI
import Charts
import CiteKitCore

/// Aggregate local counters. Existing history contributes library totals, not invented past events.
@MainActor final class ActivityStats: ObservableObject {
    static let shared = ActivityStats()
    struct Snapshot: Codable {
        var since = Date()
        var generated = 0
        var copied = 0
        var searches = 0
        var dailyGenerated: [String: Int] = [:]
    }
    @Published private(set) var snapshot: Snapshot
    private let defaults: UserDefaults
    private let key = "dashboardActivity.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
    }
    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
    enum Event { case generated, copied, search }
    func record(_ event: Event, at date: Date = Date()) {
        switch event {
        case .generated:
            snapshot.generated += 1
            snapshot.dailyGenerated[Self.dayKey(date), default: 0] += 1
        case .copied: snapshot.copied += 1
        case .search: snapshot.searches += 1
        }
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }
    var week: [(date: Date, count: Int)] {
        (-6...0).compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) else { return nil }
            return (day, snapshot.dailyGenerated[Self.dayKey(day), default: 0])
        }
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case overview = "Overview", history = "History", commands = "Commands"
    var id: String { rawValue }
    var icon: String {
        switch self { case .overview: return "square.grid.2x2"; case .history: return "books.vertical"; case .commands: return "keyboard" }
    }
}

struct DashboardView: View {
    @ObservedObject var repository: CitationRepository
    @ObservedObject var state: AppState
    @ObservedObject private var activity = ActivityStats.shared
    @ObservedObject private var preferences = Preferences.shared
    @State private var section = DashboardSection.overview
    var onCapture: () -> Void
    var onSearch: () -> Void
    var onSettings: () -> Void
    var onFullScreen: () -> Void
    private let accent = Color.teal
    private var quotes: Int { repository.records.reduce(0) { $0 + $1.quotes.count } }
    private var reviewCount: Int {
        repository.records.filter { record in
            guard let level = record.item?.confidence.level else { return true }
            return level == .medium || level == .low
        }.count
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(section.rawValue).font(.headline)
                    Spacer()
                    Button(action: onSearch) { Label("Find sources", systemImage: "magnifyingglass") }
                    Button(action: onCapture) { Label("New citation", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(accent)
                    Button(action: onFullScreen) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Toggle full screen").accessibilityLabel("Toggle dashboard full screen")
                }.padding(20)
                Divider()
                switch section {
                case .overview: overview
                case .history: HistoryView(state: state, repository: repository)
                case .commands: commands
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1040, minHeight: 680)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image(systemName: "text.quote").font(.title2).foregroundStyle(accent)
                    .padding(10).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading) { Text("CiteKit").font(.title2.bold()); Text("Your research library").font(.caption).foregroundStyle(.secondary) }
            }
            VStack(spacing: 8) {
                ForEach(DashboardSection.allCases) { tab in
                    Button { section = tab } label: {
                        Label(tab.rawValue, systemImage: tab.icon).font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(section == tab ? accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).foregroundStyle(section == tab ? accent : Color.primary)
                }
            }
            Spacer()
            Label("Stored on this Mac", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
            Button(action: onSettings) { Label("Preferences", systemImage: "gearshape") }.buttonStyle(.plain)
        }.padding(22).frame(width: 220).frame(maxHeight: .infinity)
            .background(.ultraThinMaterial)
    }
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A home for your research.").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Revisit sources, check your progress, and pick up where you left off.").foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    metric("Saved sources", value: repository.records.count, icon: "books.vertical", note: "In your library")
                    metric("Saved quotes", value: quotes, icon: "quote.opening", note: "Attached to sources")
                    metric("Needs review", value: reviewCount, icon: "checkmark.shield", note: "Medium or low confidence")
                    metric("Copies", value: activity.snapshot.copied, icon: "doc.on.doc", note: "Citation copy actions")
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Citation activity").font(.headline)
                        Text("Successful generations · last 7 days").font(.caption).foregroundStyle(.secondary)
                        Chart(activity.week, id: \.date) { day in
                            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Citations", day.count))
                                .foregroundStyle(accent.gradient).cornerRadius(5)
                                .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(day.count) citations")
                        }.chartYScale(domain: 0...max(1, activity.week.map(\.count).max() ?? 0))
                            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                            .frame(height: 160)
                        Text("\(activity.snapshot.generated) generations · \(activity.snapshot.searches) successful searches").font(.caption)
                        Text("Activity tracked since \(activity.snapshot.since.formatted(date: .abbreviated, time: .omitted)). Earlier activity is not reconstructed.").font(.caption2).foregroundStyle(.secondary)
                    }.dashboardCard()
                    VStack(alignment: .leading, spacing: 18) {
                        Text("At your fingertips").font(.headline)
                        shortcut("Cite selected URL", keys: preferences.shortcut.label, detail: "Highlight a link in your document, then invoke CiteKit.")
                        shortcut("Find a source", keys: preferences.searchShortcut.label, detail: "Select a title, author, or partial reference to see suggested sources.")
                        Button("View all commands") { section = .commands }.buttonStyle(.link)
                    }.frame(width: 245).dashboardCard()
                }
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Recently saved").font(.headline); Spacer(); Button("View history") { section = .history }.buttonStyle(.link) }
                    if repository.records.isEmpty {
                        ContentUnavailableView("Your library starts here", systemImage: "books.vertical", description: Text("Generate a citation to save your first source automatically."))
                    }
                    ForEach(Array(repository.records.prefix(5))) { record in
                        Button { state.load(record); section = .history } label: {
                            HStack(spacing: 14) {
                                Image(systemName: record.item?.type == "book" ? "book.closed" : "doc.text").foregroundStyle(accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.item?.title ?? "Unavailable source").font(.callout.weight(.medium)).lineLimit(2)
                                    Text(record.item?.authors.map(\.display).joined(separator: ", ") ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(record.item?.health ?? "Needs review").font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if record.id != repository.records.prefix(5).last?.id { Divider() }
                    }
                }.dashboardCard()
            }.padding(28).frame(maxWidth: 1400)
        }
    }
    private func metric(_ title: String, value: Int, icon: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value.formatted()).font(.system(size: 32, weight: .semibold, design: .rounded))
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).dashboardCard()
    }
    private func shortcut(_ title: String, keys: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title).font(.callout.weight(.medium)); Spacer(); Text(keys).font(.system(.caption, design: .monospaced)).padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 5)) }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var commands: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Less switching. More writing.").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Global shortcuts work from other apps. Copy shortcuts work inside the citation panel.").foregroundStyle(.secondary)
                VStack(spacing: 22) {
                    shortcut("Capture a source or quote", keys: preferences.shortcut.label, detail: "Select an actual URL or identifier to generate a citation. Selected prose becomes a quote; add its source and page number manually.")
                    shortcut("Search for a source", keys: preferences.searchShortcut.label, detail: "Highlight a title, author, year, or publication. Review the suggestions, then choose Cite this source.")
                    Divider()
                    shortcut("Primary copy action", keys: "⌘1", detail: "Copies the full citation, the in-text citation, or asks which one—according to Preferences.")
                    shortcut("Copy in-text citation", keys: "⌘2", detail: "Include a page locator by entering it beside the in-text citation.")
                    shortcut("Copy BibTeX", keys: "⌘3", detail: "Copy a bibliography entry for LaTeX and reference tools.")
                    shortcut("Copy quote + citation", keys: "⌘4", detail: "With a quote and source loaded, copy the passage with an MLA or APA in-text citation.")
                    shortcut("Dismiss the capture panel", keys: "esc", detail: "CiteKit continues running in the menu bar.")
                }.dashboardCard()
                VStack(alignment: .leading, spacing: 12) {
                    Label("Enable selection capture", systemImage: "cursorarrow.rays").font(.headline)
                    Text("Allow CiteKit in System Settings → Privacy & Security → Accessibility. Some editors do not expose their selection; use Paste Source or Cite Clipboard instead.").foregroundStyle(.secondary)
                    Button("Open Accessibility permission prompt") { SelectionReader.requestPermission() }
                    Text("Confidence describes citation metadata, not research quality. Review flagged sources in History. Quotes and history stay on this Mac; explicit lookups and searches send the input to the relevant provider.").font(.caption).foregroundStyle(.secondary)
                }.dashboardCard()
            }.padding(28).frame(maxWidth: 1000)
        }.frame(maxWidth: .infinity)
    }
}
private extension View {
    func dashboardCard() -> some View {
        self.padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)))
    }
}
