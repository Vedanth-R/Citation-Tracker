import SwiftUI
import CoreData
import CiteKitCore

@main struct CiteKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var preferences = Preferences.shared
    var body: some Scene {
        MenuBarExtra("CiteKit", systemImage: "text.quote", isInserted: $preferences.showMenuBar) {
            Button("Cite Selected Text    \(preferences.shortcut.label)") { delegate.capture() }
            Button("Cite Clipboard") { delegate.clipboard() }
            Button("Paste Source…") { delegate.panel.show(state: delegate.state) }
            Divider()
            Button("History") { delegate.showHistory() }
            Button("Preferences…") { delegate.showSettings() }
            Divider()
            Button("Quit CiteKit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    let panel = PanelController()
    let historyState = AppState()
    let hotkey = GlobalHotkey()
    var repository: CitationRepository?
    var historyWindow: NSWindow?
    var settingsWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Preferences.shared.showMenuBar ? .accessory : .regular)
        do {
            let repository = try CitationRepository()
            self.repository = repository; state.repository = repository; historyState.repository = repository
        } catch { state.error = "Local history could not open: \(error.localizedDescription). Citations can still be copied." }
        panel.onHistory = { [weak self] in self?.showHistory() }
        panel.onSettings = { [weak self] in self?.showSettings() }
        Preferences.shared.updateZoteroService()
        hotkey.action = { [weak self] in self?.capture() }
        Preferences.shared.applyShortcut = { [weak self] shortcut in self?.hotkey.register(shortcut) ?? false }
        if !hotkey.register(Preferences.shared.shortcut) { Preferences.shared.shortcutError = "The saved shortcut is unavailable. Choose another in Preferences."; state.error = Preferences.shared.shortcutError }
        if !UserDefaults.standard.bool(forKey: "hasOpened") { panel.show(state: state); UserDefaults.standard.set(true, forKey: "hasOpened") }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { LocalZoteroServer.shared.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { panel.show(state: state); return true }
    func capture() {
        state.sourceApplication = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let selected = SelectionReader.read()
        state.resetCapture(); state.input = ""; state.quote = ""; state.page = ""
        if let selected {
            if case .text = SourceClassifier.classify(selected) {
                state.quote = selected; state.input = ""; state.item = nil; state.output = nil
                state.notice = "Quote captured. Add its source URL or DOI."
            } else { state.input = selected; state.generate() }
        } else { state.notice = SelectionReader.trusted ? "This app did not expose selected text. Copy the highlighted URL, then choose Cite Clipboard." : "Enable Accessibility for CiteKit, then return to your document, highlight its URL text, and press the shortcut again." }
        panel.show(state: state)
    }
    func clipboard() { state.input = NSPasteboard.general.string(forType: .string) ?? ""; state.quote = ""; state.page = ""; panel.show(state: state); if !state.input.isEmpty { state.generate() } }
    func showHistory() {
        guard let repository else { panel.show(state: state); return }
        if historyWindow == nil {
            historyWindow = makeWindow("Research history", width: 820, height: 610, content: HistoryView(state: historyState, repository: repository))
        }
        historyWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showSettings() {
        if settingsWindow == nil { settingsWindow = makeWindow("CiteKit Preferences", width: 620, height: 760, content: PreferencesView()) }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func makeWindow<V: View>(_ title: String, width: CGFloat, height: CGFloat, content: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.contentView = NSHostingView(rootView: content); window.center(); return window
    }
}
