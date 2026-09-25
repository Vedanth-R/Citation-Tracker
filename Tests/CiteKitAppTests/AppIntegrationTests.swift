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
