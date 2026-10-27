import AppKit
import Carbon
import ServiceManagement
import Testing
import CiteKitCore
@testable import CiteKitApp

@Suite(.serialized) @MainActor struct SettingsTests {
    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let name = "CiteKitSettingsTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }
    @Test func settingsPersistAndUnknownValuesFallBack() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let app = NSApplication.shared
        let previous = app.appearance
        defer { app.appearance = previous }
        let settings = Preferences(defaults: defaults)
        #expect(settings.appearance == .system)
        settings.appearance = .dark; settings.style = .apa; settings.copyBehavior = .ask
        settings.pubmed = false; settings.arxiv = false; settings.isbn = false; settings.compareWeb = false
        let restored = Preferences(defaults: defaults)
        #expect(restored.appearance == .dark)
        #expect(restored.style == .apa)
        #expect(restored.copyBehavior == .ask)
        #expect(!restored.resolverOptions.usePubMed && !restored.resolverOptions.useArxiv && !restored.resolverOptions.useISBN)
        #expect(!restored.resolverOptions.compareWebMetadata)
        defaults.set("unknown", forKey: "appearance"); defaults.set("unknown", forKey: "defaultStyle")
        let fallback = Preferences(defaults: defaults)
        #expect(fallback.appearance == .system && fallback.style == .mla)
    }
    @Test func popupInheritsLiveLightDarkAndSystemAppearance() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let app = NSApplication.shared
        let previous = app.appearance
        defer { app.appearance = previous }
        let panel = CitationPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = NSView()
        let settings = Preferences(defaults: defaults)
        for mode in [AppAppearance.light, .dark] {
            settings.appearance = mode
            let expected: NSAppearance.Name = mode == .light ? .aqua : .darkAqua
            #expect(panel.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
            #expect(panel.contentView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == expected)
        }
        settings.appearance = .system
        #expect(app.appearance == nil)
    }
    @Test func shortcutConflictAndRegistrationFailureKeepOldValue() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = Preferences(defaults: defaults)
        settings.applyShortcut = { _ in true }
        settings.setShortcut(settings.searchShortcut)
        #expect(settings.shortcut == .standard)
        #expect(settings.shortcutError != nil)
        let replacement = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | cmdKey), label: "⌃⌘K")
        settings.applyShortcut = { _ in false }; settings.setShortcut(replacement)
        #expect(settings.shortcut == .standard)
        settings.applyShortcut = { _ in true }; settings.setShortcut(replacement)
        #expect(settings.shortcut == replacement && settings.shortcutError == nil)
        #expect(Preferences(defaults: defaults).shortcut == replacement)
        settings.applySearchShortcut = { _ in true }; settings.setSearchShortcut(replacement)
        #expect(settings.searchShortcut == .search)
    }
    @Test func loginRegistrationApprovalAndFailureAreReported() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var status = SMAppService.Status.notRegistered
        var actions: [Bool] = []
        let settings = Preferences(defaults: defaults, loginAction: { enabled in
            actions.append(enabled); status = enabled ? .requiresApproval : .notRegistered
        }, readLoginStatus: { status })
        settings.setLogin(true)
        #expect(actions == [true] && settings.loginStatus == .requiresApproval && settings.loginError == nil)
        settings.setLogin(false)
        #expect(actions == [true, false] && settings.loginStatus == .notRegistered)
        let failing = Preferences(defaults: defaults, loginAction: { _ in throw CocoaError(.fileWriteNoPermission) }, readLoginStatus: { .notRegistered })
        failing.setLogin(true)
        #expect(failing.loginError != nil && failing.loginStatus == .notRegistered)
    }
    @Test func customServerRejectsUnsafeOrInvalidAddresses() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = Preferences(defaults: defaults)
        let original = settings.zoteroURL
        #expect(!settings.saveCustomZoteroURL("http://example.org"))
        #expect(!settings.saveCustomZoteroURL("https://example.org/web"))
        #expect(settings.zoteroURL == original)
        #expect(settings.saveCustomZoteroURL("https://example.org"))
        #expect(Preferences(defaults: defaults).zoteroURL == "https://example.org")
    }
    @Test func historyAndQuotesSurviveDiskReopenAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var item = CitationItem(title: "Persistent test source", url: "https://example.org/source")
        item.doi = "10.1234/persistence"
        let record = try CitationRecord(item)
        record.quotes = [QuoteRecord(text: "Test passage", page: "12", application: "Test")]
        do {
            let repository = try CitationRepository(storageDirectory: directory)
            try repository.save(record)
        }
        do {
            let reopened = try CitationRepository(storageDirectory: directory)
            #expect(reopened.records.count == 1)
            #expect(reopened.records.first?.item?.title == item.title)
            #expect(reopened.records.first?.quotes.first?.page == "12")
            try reopened.delete(try #require(reopened.records.first))
        }
        #expect(try CitationRepository(storageDirectory: directory).records.isEmpty)
    }
}
