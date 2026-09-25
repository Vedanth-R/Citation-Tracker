import AppKit
import SwiftUI
import Carbon
import ServiceManagement
import CiteKitCore

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let standard = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey | cmdKey), label: "⌥⌘C")
    static func from(_ event: NSEvent) -> KeyboardShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), flags.contains(.option) || flags.contains(.control), !event.isARepeat,
              let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1, key.first?.isLetter == true || key.first?.isNumber == true else { return nil }
        var modifiers: UInt32 = UInt32(cmdKey)
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        label += "⌘" + key
        return KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label)
    }
}
enum CopyBehavior: String, CaseIterable { case full = "Full citation", inText = "In-text citation", ask = "Ask every time" }
@MainActor final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var style: CitationStyle { didSet { defaults.set(style.rawValue, forKey: "defaultStyle") } }
    @Published var copyBehavior: CopyBehavior { didSet { defaults.set(copyBehavior.rawValue, forKey: "copyBehavior") } }
    @Published var showMenuBar: Bool { didSet { defaults.set(showMenuBar, forKey: "showMenuBar"); NSApp.setActivationPolicy(showMenuBar ? .accessory : .regular) } }
    @Published var pubmed: Bool { didSet { defaults.set(pubmed, forKey: "providerPubMed") } }
    @Published var arxiv: Bool { didSet { defaults.set(arxiv, forKey: "providerArxiv") } }
    @Published var isbn: Bool { didSet { defaults.set(isbn, forKey: "providerISBN") } }
    @Published var compareWeb: Bool { didSet { defaults.set(compareWeb, forKey: "compareWeb") } }
    @Published private(set) var zoteroURL: String
    @Published private(set) var zoteroEnabled: Bool
    @Published private(set) var zoteroCustomServer: Bool
    @Published private(set) var shortcut: KeyboardShortcut
    @Published var shortcutError: String?
    @Published var loginError: String?
    @Published var loginStatus = SMAppService.mainApp.status
    var applyShortcut: ((KeyboardShortcut) -> Bool)?
    private let defaults = UserDefaults.standard
    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["showMenuBar": true, "providerPubMed": true, "providerArxiv": true, "providerISBN": true, "compareWeb": true])
        style = CitationStyle(rawValue: d.string(forKey: "defaultStyle") ?? "") ?? .mla
        copyBehavior = CopyBehavior(rawValue: d.string(forKey: "copyBehavior") ?? "") ?? .full
        showMenuBar = d.bool(forKey: "showMenuBar"); pubmed = d.bool(forKey: "providerPubMed"); arxiv = d.bool(forKey: "providerArxiv"); isbn = d.bool(forKey: "providerISBN"); compareWeb = d.bool(forKey: "compareWeb")
        zoteroURL = d.string(forKey: "zoteroURL") ?? "http://127.0.0.1:1969"; zoteroEnabled = d.bool(forKey: "zoteroEnabled")
        zoteroCustomServer = d.object(forKey: "zoteroCustomServer") != nil ? d.bool(forKey: "zoteroCustomServer") : !["http://127.0.0.1:1969", "http://localhost:1969"].contains(d.string(forKey: "zoteroURL") ?? "http://127.0.0.1:1969")
        shortcut = d.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(KeyboardShortcut.self, from: $0) } ?? .standard
    }
    var resolverOptions: ResolverOptions {
        var options = ResolverOptions(); options.usePubMed = pubmed; options.useArxiv = arxiv; options.useISBN = isbn; options.compareWebMetadata = compareWeb
        if zoteroEnabled && zoteroCustomServer { options.zoteroEndpoint = ResolverOptions.validZoteroEndpoint(zoteroURL) }
        return options
    }
    func setShortcut(_ value: KeyboardShortcut) {
        guard applyShortcut?(value) == true else { shortcutError = "This shortcut could not be registered. Your previous shortcut is still active."; return }
        shortcut = value; defaults.set(try? JSONEncoder().encode(value), forKey: "shortcut"); shortcutError = nil
    }
    func setZoteroEnabled(_ enabled: Bool) {
        zoteroEnabled = enabled; defaults.set(enabled, forKey: "zoteroEnabled")
        updateZoteroService()
    }
    func setZoteroCustomServer(_ enabled: Bool) {
        zoteroCustomServer = enabled; defaults.set(enabled, forKey: "zoteroCustomServer")
        updateZoteroService()
    }
    func updateZoteroService() {
        if zoteroEnabled && !zoteroCustomServer {
            Task {
                guard self.zoteroEnabled && !self.zoteroCustomServer else { return }
                _ = try? await LocalZoteroServer.shared.ensureRunning()
            }
        } else { LocalZoteroServer.shared.stop() }
    }
    func saveCustomZoteroURL(_ url: String) -> Bool {
        guard ResolverOptions.validZoteroEndpoint(url) != nil else { return false }
        zoteroURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(zoteroURL, forKey: "zoteroURL"); return true
    }
    func preparedResolverOptions() async -> ResolverOptions {
        var options = resolverOptions
        guard zoteroEnabled && !zoteroCustomServer else { return options }
        do {
            let connection = try await LocalZoteroServer.shared.ensureRunning()
            // A toggle or mode change during startup takes precedence over this lookup.
            guard zoteroEnabled && !zoteroCustomServer else { return resolverOptions }
            options.zoteroEndpoint = connection.endpoint
            options.zoteroAuthorizationToken = connection.token
        } catch {
            guard zoteroEnabled && !zoteroCustomServer else { return resolverOptions }
            options.zoteroStartupIssue = error.localizedDescription
        }
        return options
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        loginStatus = SMAppService.mainApp.status
    }
}
private final class ShortcutField: NSTextField {
    var onShortcut: ((KeyboardShortcut) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); stringValue = "Press ⌘ plus ⌥ or ⌃ and a letter…" }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { window?.makeFirstResponder(nil); return }
        if let shortcut = KeyboardShortcut.from(event) { onShortcut?(shortcut); window?.makeFirstResponder(nil) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event); return true
    }
}
struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var preferences: Preferences
    func makeNSView(context: Context) -> NSTextField {
        let field = ShortcutField(); field.isEditable = false; field.isSelectable = false; field.isBezeled = true; field.alignment = .center
        field.onShortcut = { preferences.setShortcut($0) }; field.setAccessibilityLabel("Global citation shortcut. Click and press Command, Option or Control, and a letter.")
        return field
    }
    func updateNSView(_ view: NSTextField, context: Context) { view.stringValue = preferences.shortcut.label }
}
struct PreferencesView: View {
    @ObservedObject var preferences = Preferences.shared
    @State private var zoteroDraft = ""
    @ObservedObject private var localZotero = LocalZoteroServer.shared
    @State private var providerMessage = ""
    var body: some View {
        Form {
            Section("General") {
                Picker("Default citation style", selection: $preferences.style) { ForEach(CitationStyle.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Primary Copy action", selection: $preferences.copyBehavior) { ForEach(CopyBehavior.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Show menu-bar icon", isOn: $preferences.showMenuBar)
                Text("When the menu-bar icon is hidden, CiteKit appears in the Dock so you can reopen it.").font(.caption).foregroundStyle(.secondary)
                Toggle("Launch CiteKit at login", isOn: Binding(get: { preferences.loginStatus == .enabled || preferences.loginStatus == .requiresApproval }, set: preferences.setLogin))
                if preferences.loginStatus == .requiresApproval { Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() } }
                if let error = preferences.loginError { Text(error).foregroundStyle(.orange) }
            }
            Section("Highlight → shortcut → citation") {
                HStack { Text("Global shortcut"); ShortcutRecorder(preferences: preferences).frame(width: 255, height: 26); Button("Reset") { preferences.setShortcut(.standard) } }
                Text("Click the shortcut, then press Command with Option or Control and a letter/number. Changes take effect immediately.").font(.caption).foregroundStyle(.secondary)
                if let error = preferences.shortcutError { Text(error).foregroundStyle(.orange) }
                Button("Enable Accessibility…") { SelectionReader.requestPermission() }
                Text("Highlight the URL text in your document, then press the shortcut. Apps must expose their selection through macOS Accessibility. If they do not, copy the URL and choose Cite Clipboard.").font(.caption)
            }
            Section("Metadata & verification") {
                Toggle("PubMed biomedical articles", isOn: $preferences.pubmed)
                Toggle("arXiv preprints", isOn: $preferences.arxiv)
                Toggle("ISBN books via Open Library", isOn: $preferences.isbn)
                Toggle("Compare identifier results with webpage metadata", isOn: $preferences.compareWeb)
                Text("Additional checks can take longer. Differences and unavailable providers appear in Source Health.").font(.caption).foregroundStyle(.secondary)
                Toggle("Use Zotero", isOn: Binding(get: { preferences.zoteroEnabled }, set: preferences.setZoteroEnabled))
                Text("CiteKit starts Zotero automatically on this Mac when enabled. No separate setup is needed. Quote text is never sent.").font(.caption).foregroundStyle(.secondary)
                if preferences.zoteroEnabled && !preferences.zoteroCustomServer {
                    Label(localZotero.status, systemImage: localZotero.isReady ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(localZotero.isReady ? .green : .secondary)
                    if let error = localZotero.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("Retry Zotero") { preferences.updateZoteroService() }
                    }
                }
                DisclosureGroup("Advanced Zotero connection") {
                    Toggle("Use a custom server instead", isOn: Binding(get: { preferences.zoteroCustomServer }, set: preferences.setZoteroCustomServer))
                    if preferences.zoteroCustomServer {
                        TextField("Server base URL", text: $zoteroDraft).textFieldStyle(.roundedBorder)
                        Text("For an existing Translation Server. Source URLs are sent to this server; remote connections require HTTPS.").font(.caption).foregroundStyle(.secondary)
                        Button("Save Server Address") { providerMessage = preferences.saveCustomZoteroURL(zoteroDraft) ? "Server address saved." : "Enter an HTTPS base URL, or HTTP on localhost, without /web." }
                        if !providerMessage.isEmpty { Text(providerMessage).font(.caption) }
                    }
                }
            }
            Section("Privacy") { Text("Selection is read only when you invoke CiteKit. History and quotes stay on this Mac. Only source URLs and identifiers are used for provider lookups.").font(.caption) }
        }.formStyle(.grouped).frame(minWidth: 580, minHeight: 650)
        .onAppear { zoteroDraft = preferences.zoteroURL; preferences.loginStatus = SMAppService.mainApp.status }
    }
}
