import AppKit
import Carbon
import Testing
import CiteKitCore
@testable import CiteKitApp

@MainActor struct AppIntegrationTests {
    @Test func documentSelectionUsesUTF16Offsets() {
        let document = "📚 Source: https://example.org/article and other text"
        let range = (document as NSString).range(of: "https://example.org/article")
        let selected = SelectionReader.selectedSubstring(document, range: CFRange(location: range.location, length: range.length))
        #expect(selected == "https://example.org/article")
        #expect(SourceClassifier.classify(selected!) == .url(URL(string: selected!)!))
        #expect(SelectionReader.selectedSubstring(document, range: CFRange(location: -1, length: 10)) == nil)
        #expect(SelectionReader.selectedSubstring(document, range: CFRange(location: 0, length: Int.max)) == nil)
        #expect(SelectionReader.selectedSubstring(document, range: CFRange(location: 0, length: 0)) == nil)
    }
    @Test func shortcutRecorderCapturesModifiersAndRejectsPlainTyping() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option, .command], timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: UInt16(kVK_ANSI_C)))
        #expect(KeyboardShortcut.from(event) == .standard)
        let plain = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: UInt16(kVK_ANSI_C)))
        #expect(KeyboardShortcut.from(plain) == nil)
    }
    @Test func repositoryKeepsQuotesAcrossMetadataUpdates() throws {
        let repository = try CitationRepository(inMemory: true)
        var item = CitationItem(title: "Original", url: "https://example.org/article")
        item.doi = "10.1234/example"
        let record = try CitationRecord(item)
        record.quotes.append(QuoteRecord(text: "A selected quote", page: "42", application: "TextEdit"))
        try repository.save(record)
        item.title = "Updated"
        record.payload = try JSONEncoder().encode(item)
        try repository.save(record)
        #expect(repository.records.count == 1)
        #expect(repository.records[0].item?.title == "Updated")
        #expect(repository.records[0].quotes.first?.page == "42")
        try repository.delete(record)
        #expect(repository.records.isEmpty)
    }
}

@MainActor struct SourceSearchFlowTests {
    @Test func searchDoesNotSaveUnconfirmedCandidates() async throws {
        let state = AppState()
        let repository = try CitationRepository(inMemory: true)
        state.repository = repository
        state.sourceSearch = SourceSearch(client: HTTPClient { _ in
            Data(#"{"message":{"items":[{"DOI":"10.1234/test","title":["Candidate"]}]}}"#.utf8)
        })
        state.beginSearch("Candidate")
        state.searchSources()
        for _ in 0..<100 where state.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(!state.busy)
        #expect(state.searchResults.count == 1)
        #expect(state.item == nil)
        #expect(repository.records.isEmpty)
        state.resetCapture()
        #expect(state.searchResults.isEmpty)
        #expect(!state.searching)
    }
    @Test func clearedSearchCannotRestoreLateResults() async throws {
        let state = AppState()
        state.sourceSearch = SourceSearch(client: HTTPClient { _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return Data(#"{"message":{"items":[{"DOI":"10.1234/late","title":["Late result"]}]}}"#.utf8)
        })
        state.beginSearch("Old query"); state.searchSources()
        await Task.yield()
        state.resetCapture()
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(state.searchResults.isEmpty)
        #expect(state.searchedQuery == nil)
        #expect(!state.busy)
    }
}
