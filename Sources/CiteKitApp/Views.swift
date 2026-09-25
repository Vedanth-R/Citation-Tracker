import SwiftUI
import AppKit
import CoreData
import CiteKitCore

struct SpotlightMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
private struct KeyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.06)))
    }
}
struct CaptureView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var preferences = Preferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var sourceFocused: Bool
    @State private var chooseCopy = false
    @State private var healthOpen = false
    @State private var conflictsOpen = false
    @State private var quoteOpen = false
    var onDismiss: (() -> Void)?
    var onHistory: (() -> Void)?
    var onSettings: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    private var transition: AnyTransition { reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)) }
    private var animation: Animation { .easeInOut(duration: reduceMotion ? 0 : 0.18) }
    private var desiredHeight: CGFloat {
        let base: CGFloat = state.item != nil ? 540 : state.busy ? 210 : 255
        return base + (!SelectionReader.trusted ? 54 : 0) + (state.error != nil ? 66 : 0) + (quoteOpen ? 155 : 0) + (healthOpen || conflictsOpen ? 190 : 0)
    }
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !SelectionReader.trusted { permissionHint }
                    if let error = state.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled).transition(transition)
                    }
                    if state.busy {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Finding your source…").font(.callout.weight(.medium))
                                Text("Retrieving metadata and checking for discrepancies").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading).transition(transition)
                    } else if let item = state.item {
                        result(item).transition(transition)
                    } else {
                        emptyState.transition(transition)
                    }
                    if quoteOpen { quoteEditor.transition(transition) }
                }.padding(.horizontal, 24).padding(.vertical, 18)
            }.scrollIndicators(.hidden)
            footer
        }
        .background(SpotlightMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.75))
        .tint(.accentColor)
        .frame(minWidth: 470)
        .animation(animation, value: state.busy)
        .animation(animation, value: state.item?.id)
        .animation(animation, value: quoteOpen)
        .animation(animation, value: healthOpen)
        .animation(animation, value: conflictsOpen)
        .onAppear { quoteOpen = !state.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty; onHeightChange?(desiredHeight) }
        .onChange(of: desiredHeight) { onHeightChange?(desiredHeight) }
        .onChange(of: state.quote) { if !state.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { quoteOpen = true } }
        .onReceive(NotificationCenter.default.publisher(for: .citeKitPanelOpened)) { _ in
            guard onDismiss != nil else { return }
            sourceFocused = state.item == nil && !state.busy
            quoteOpen = !state.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            onHeightChange?(desiredHeight)
        }
        .onExitCommand { onDismiss?() }
    }
    private var searchBar: some View {
        HStack(spacing: 15) {
            Image(systemName: "magnifyingglass").font(.system(size: 23, weight: .regular)).foregroundStyle(.secondary)
            TextField("Cite a source…", text: $state.input)
                .font(.system(size: 22, weight: .regular)).textFieldStyle(.plain)
                .focused($sourceFocused).accessibilityLabel("Source URL, DOI, PMID, arXiv ID, or ISBN")
                .onSubmit { if !state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.busy { sourceFocused = false; state.generate() } }
            if !state.input.isEmpty {
                Button { state.resetCapture(); state.input = ""; sourceFocused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help("Clear source").accessibilityLabel("Clear source")
            }
            Button { sourceFocused = false; state.generate() } label: {
                Image(systemName: "arrow.turn.down.left").font(.system(size: 14, weight: .medium))
                    .frame(width: 31, height: 29).background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).disabled(state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.busy)
                .help("Generate citation (Return)").accessibilityLabel("Generate citation")
        }.padding(.horizontal, 24).frame(height: 76)
    }
    private var permissionHint: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "cursorarrow.rays").foregroundStyle(.secondary)
            Text("Cite highlighted text from other apps.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Enable Access…") { SelectionReader.requestPermission() }.buttonStyle(.link).font(.caption)
                .help("Accessibility is used only to read your selection when you invoke CiteKit.")
        }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Your next citation starts here.").font(.system(size: 15, weight: .medium))
            Text("Paste a URL, DOI, PMID, arXiv ID, or ISBN.").font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 9) {
                Button { state.input = NSPasteboard.general.string(forType: .string) ?? ""; sourceFocused = true } label: { Label("Use clipboard", systemImage: "doc.on.clipboard") }
                Button { quoteOpen.toggle() } label: { Label("Capture a quote", systemImage: "quote.opening") }
            }.controlSize(.small).buttonStyle(.bordered)
        }.padding(.vertical, 4)
    }
    private func result(_ item: CitationItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: item.type == "book" ? "book.closed" : "doc.text")
                Text(item.type == "book" ? "BOOK" : item.arxivID != nil ? "PREPRINT" : item.type == "article-journal" ? "JOURNAL ARTICLE" : "SOURCE")
                    .tracking(1.3)
                Spacer()
                confidenceBadge(item)
            }.font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title).font(.system(size: 21, weight: .semibold)).tracking(-0.35).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text([item.authors.map(\.display).joined(separator: ", "), item.container, item.year.map(String.init) ?? "No date"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
            if let issue = item.confidence.issues.first, item.confidence.level != .verified {
                Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            HStack {
                Picker("Citation style", selection: $state.style) { ForEach(CitationStyle.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 270)
                Spacer()
                Button { quoteOpen.toggle() } label: { Image(systemName: "quote.bubble").font(.system(size: 14)) }
                    .buttonStyle(.plain).foregroundStyle(quoteOpen ? Color.accentColor : .secondary).help("Capture a quote").accessibilityLabel("Capture a quote")
            }
            if let output = state.output {
                VStack(alignment: .leading, spacing: 14) {
                    Text(output.full).font(.system(size: 14, design: state.style == .bibtex ? .monospaced : .default)).lineSpacing(4)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12) {
                        Button { copyPreferred(output) } label: {
                            HStack(spacing: 8) { Image(systemName: "doc.on.doc"); Text("Copy citation"); Text("⌘1").opacity(0.65) }.font(.system(size: 12, weight: .medium))
                        }.buttonStyle(.borderedProminent).keyboardShortcut("1")
                        .confirmationDialog("Copy citation", isPresented: $chooseCopy) {
                            Button("Full citation") { state.copy(output.full) }
                            if !output.inText.isEmpty { Button("In-text citation") { state.copy(output.inText) } }
                            Button("BibTeX") { state.copy(CitationFormatter().bibtex(item)) }
                        }
                        Spacer()
                        Menu {
                            Button("Copy full citation") { state.copy(output.full) }
                            Button("Copy BibTeX") { state.copy(CitationFormatter().bibtex(item)) }.keyboardShortcut("3")
                            if state.style == .apa { Button("Copy APA narrative") { state.copy(output.narrative) } }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("More copy options")
                    }
                }.padding(16).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.055)))
                if !output.inText.isEmpty {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("IN-TEXT").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                            Text(output.inText).font(.system(size: 13)).textSelection(.enabled)
                        }
                        Spacer(minLength: 8)
                        TextField("Page", text: $state.page).textFieldStyle(.roundedBorder).frame(width: 78)
                            .accessibilityLabel("Page or page range").onChange(of: state.page) { state.refresh() }
                        Button { state.copy(output.inText) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).keyboardShortcut("2").help("Copy in-text citation (⌘2)").accessibilityLabel("Copy in-text citation")
                    }.padding(.horizontal, 2)
                }
            }
            DisclosureGroup(isExpanded: $healthOpen) { healthDetails(item).padding(.top, 10) } label: {
                HStack { Text("Source health"); Spacer(); Text("\(item.confidence.issues.count) \(item.confidence.issues.count == 1 ? "note" : "notes")").foregroundStyle(.tertiary) }.font(.caption)
            }.tint(.secondary)
            if let conflicts = item.conflicts, !conflicts.isEmpty {
                DisclosureGroup("Metadata conflicts (\(conflicts.count))", isExpanded: $conflictsOpen) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(conflicts) { conflict in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(conflict.field.capitalized).font(.callout.weight(.medium))
                                ForEach(conflict.alternatives) { option in
                                    HStack(alignment: .top) {
                                        Image(systemName: option.provider == conflict.selectedProvider ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 3) { Text(option.display).textSelection(.enabled); Text(option.provider).foregroundStyle(.secondary) }
                                        Spacer()
                                        if conflict.field != "doi" { Button("Use") { state.chooseConflict(field: conflict.field, provider: option.provider) }.controlSize(.small) }
                                    }.font(.caption)
                                }
                                if conflict.field == "doi" { Text("Paste the intended DOI above to verify it separately.").font(.caption).foregroundStyle(.orange) }
                            }
                        }
                    }.padding(.top, 10)
                }.font(.caption).tint(.orange)
            }
        }
    }
    private func confidenceBadge(_ item: CitationItem) -> some View {
        let color: Color = item.confidence.level == .verified ? .green : item.confidence.level == .high ? .teal : .orange
        return Button { healthOpen.toggle() } label: {
            HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(item.health).font(.system(size: 11, weight: .medium)) }
                .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.08), in: Capsule())
        }.buttonStyle(.plain).help("Show confidence and potential issues")
    }
    private func healthDetails(_ item: CitationItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(item.confidence.summary).font(.callout)
            ForEach(item.confidence.issues, id: \.self) { Text("• " + $0).foregroundStyle(.orange) }
            Divider()
            ForEach(item.checks ?? []) { check in
                HStack(alignment: .top, spacing: 12) {
                    Text(check.provider).fontWeight(.medium).frame(width: 85, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) { Text(check.status.rawValue.capitalized); Text(check.detail).foregroundStyle(.secondary) }
                }
            }
            Divider()
            ForEach(item.evidence.keys.sorted(), id: \.self) { field in HStack { Text(field.capitalized); Spacer(); Text(item.evidence[field]!.provider).foregroundStyle(.secondary) } }
        }.font(.caption)
    }
    private var quoteEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label("Quote", systemImage: "quote.opening").font(.callout.weight(.medium)); Spacer(); Button { quoteOpen = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Collapse quote") }
            TextEditor(text: $state.quote).font(.system(size: 13)).scrollContentBackground(.hidden).frame(height: 68).padding(8)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Captured quote")
            HStack {
                Button("Save quote", action: state.saveQuote).disabled(state.item == nil || state.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Copy quote + citation") { if let output = state.output { state.copy("“\(state.quote.trimmingCharacters(in: .whitespacesAndNewlines))” \(output.inText)") } }
                    .disabled(state.output == nil || state.style == .bibtex || state.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut("4")
            }.controlSize(.small)
            if state.item == nil { Text("Add the quote’s source above. Quotes stay on this Mac.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "text.quote").font(.system(size: 12, weight: .semibold))
            Text(state.notice.isEmpty ? "CiteKit" : state.notice).font(.system(size: 11)).lineLimit(1).contentTransition(.opacity)
            Spacer(minLength: 8)
            if let onHistory { Button(action: onHistory) { Image(systemName: "clock.arrow.circlepath") }.buttonStyle(.plain).help("Citation history").accessibilityLabel("Citation history") }
            if let onSettings { Button(action: onSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Preferences").accessibilityLabel("Preferences") }
            if let onDismiss { Button(action: onDismiss) { KeyHint(text: "esc") }.buttonStyle(.plain).help("Dismiss CiteKit").accessibilityLabel("Dismiss CiteKit") }
        }.foregroundStyle(.secondary).padding(.horizontal, 21).frame(height: 40)
            .background(.primary.opacity(0.025)).overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.06)).frame(height: 0.5) }
    }
    private func copyPreferred(_ output: FormattedCitation) {
        switch preferences.copyBehavior {
        case .full: state.copy(output.full)
        case .inText: if output.inText.isEmpty { chooseCopy = true } else { state.copy(output.inText) }
        case .ask: chooseCopy = true
        }
    }
}
struct HistoryView: View {
    @ObservedObject var state: AppState
    @ObservedObject var repository: CitationRepository
    var records: [CitationRecord] { repository.records }
    @State private var search = ""
    @State private var selected: CitationRecord?
    @State private var deleteError: String?
    var filtered: [CitationRecord] { records.filter { record in guard let item = record.item else { return false }; return search.isEmpty || ([item.title, item.container, item.doi ?? ""] + item.authors.map(\.display)).joined(separator: " ").localizedCaseInsensitiveContains(search) } }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                Text("Research history").font(.title2.bold())
                TextField("Search title, author, DOI…", text: $search).textFieldStyle(.roundedBorder)
                if filtered.isEmpty { ContentUnavailableView("No saved sources", systemImage: "books.vertical", description: Text("Generate a citation to start your research history.")) }
                List(filtered) { record in
                    Button { selected = record; state.load(record) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.item?.title ?? "Unreadable record").font(.headline).lineLimit(2)
                            Text(record.item?.container ?? "").font(.caption).foregroundStyle(.secondary)
                            Text(record.lastUsed, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }.buttonStyle(.plain)
                    .contextMenu { Button("Delete Source", role: .destructive) { do { try repository.delete(record); if selected === record { selected = nil } } catch { deleteError = error.localizedDescription } } }
                }
                if let deleteError { Text(deleteError).foregroundStyle(.red) }
            }.padding().frame(minWidth: 240, idealWidth: 280)
            VStack {
                if let selected {
                    CaptureView(state: state)
                    if !selected.quotes.isEmpty {
                        DisclosureGroup("Saved quotes (\(selected.quotes.count))") {
                            ScrollView { VStack(alignment: .leading) { ForEach(selected.quotes) { quote in Button { state.quote = quote.text; state.page = quote.page; state.refresh() } label: { Text("“\(quote.text)” · \(quote.page.isEmpty ? "No page" : quote.page)").lineLimit(3) }.buttonStyle(.plain).padding(5) } } }.frame(maxHeight: 130)
                        }.padding()
                    }
                } else { ContentUnavailableView("Your research, within reach", systemImage: "text.quote", description: Text("Choose a source to copy its citation or revisit a quote.")) }
            }.frame(minWidth: 490)
        }
    }
}
