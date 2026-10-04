import SwiftUI
import CoreData
import CiteKitCore

@main struct CiteKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var preferences = Preferences.shared
    var body: some Scene {
        MenuBarExtra("CiteKit", systemImage: "text.quote", isInserted: $preferences.showMenuBar) {
            Button("Cite Selected Text    \(preferences.shortcut.label)") { delegate.capture() }
            Button("Find Sources from Selection    \(preferences.searchShortcut.label)") { delegate.searchSelection() }
            Button("Find Sources…") { delegate.startup.dismiss(); delegate.state.beginSearch(); delegate.panel.show(state: delegate.state) }
            Button("Cite Clipboard") { delegate.clipboard() }
            Button("Paste Source…") { delegate.startup.dismiss(); if delegate.state.searching { delegate.state.resetCapture(); delegate.state.input = "" }; delegate.panel.show(state: delegate.state) }
            Divider()
            Button("Dashboard") { delegate.showDashboard() }
            Button("Dashboard in Full Screen") { delegate.showDashboard(fullScreen: true) }
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
    let dashboardState = AppState()
    let hotkey = GlobalHotkey()
    let searchHotkey = GlobalHotkey()
    let startup = StartupController()
    var startupTask: Task<Void, Never>?
    var repository: CitationRepository?
    var dashboardWindow: NSWindow?
    var historyWindow: NSWindow?
    var settingsWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(Preferences.shared.showMenuBar ? .accessory : .regular)
        startup.show()
        startupTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.prepareApplication()
            let options = Preferences.shared.resolverOptions
            async let apis = StartupProbe.run(options)
            let formatter = await Task.detached { StartupProbe.formatting() }.value
            guard !Task.isCancelled else { return }
            self.startup.record(formatter)
            if !formatter.available { self.state.error = "Citation resources could not load. Rebuild or reinstall CiteKit." }
            // Readiness is awaited only when the managed service is enabled. Its existing
            // startup deadline and failure handling remain owned by LocalZoteroServer.
            if Preferences.shared.zoteroEnabled && !Preferences.shared.zoteroCustomServer {
                let ready = await Preferences.shared.preparedResolverOptions()
                self.startup.record(StartupCheck(name: "Managed Zotero", available: ready.zoteroEndpoint != nil))
            }
            for check in await apis { self.startup.record(check) }
            guard !Task.isCancelled else { return }
            let firstOpen = !UserDefaults.standard.bool(forKey: "hasOpened")
            let shouldPresent = firstOpen && !self.startup.dismissed
            self.startup.dismiss()
            if shouldPresent { self.panel.show(state: self.state) }
            UserDefaults.standard.set(true, forKey: "hasOpened")
        }
    }
    private func prepareApplication() {
        do {
            let repository = try CitationRepository()
            self.repository = repository; state.repository = repository; historyState.repository = repository; dashboardState.repository = repository
            startup.record(StartupCheck(name: "Local history", available: true))
        } catch { startup.record(StartupCheck(name: "Local history", available: false)); state.error = "Local history could not open: \(error.localizedDescription). Citations can still be copied." }
        panel.onDashboard = { [weak self] in self?.showDashboard(fullScreen: true) }
        panel.onHistory = { [weak self] in self?.showHistory() }
        panel.onSettings = { [weak self] in self?.showSettings() }
        Preferences.shared.updateZoteroService()
        searchHotkey.action = { [weak self] in self?.searchSelection() }
        Preferences.shared.applySearchShortcut = { [weak self] shortcut in self?.searchHotkey.register(shortcut) ?? false }
        if !searchHotkey.register(Preferences.shared.searchShortcut) { Preferences.shared.shortcutError = "The source search shortcut is unavailable. Choose another in Preferences." }
        hotkey.action = { [weak self] in self?.capture() }
        Preferences.shared.applyShortcut = { [weak self] shortcut in self?.hotkey.register(shortcut) ?? false }
        if !hotkey.register(Preferences.shared.shortcut) { Preferences.shared.shortcutError = "The saved shortcut is unavailable. Choose another in Preferences."; state.error = Preferences.shared.shortcutError }
        startup.record(StartupCheck(name: "Keyboard shortcuts", available: Preferences.shared.shortcutError == nil))
        startup.record(StartupCheck(name: "Selection access", available: SelectionReader.trusted))
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { startupTask?.cancel(); startup.dismiss(); LocalZoteroServer.shared.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { startup.dismiss(); panel.show(state: state); return true }
    func capture() {
        startup.dismiss()
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
    func searchSelection() {
        startup.dismiss()
        let selected = SelectionReader.read()
        state.beginSearch(selected ?? "")
        if selected == nil { state.notice = "Select reference text in your document, or paste a title, author, year, or publication here." }
        panel.show(state: state)
        if let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { state.searchSources() }
    }
    func clipboard() { startup.dismiss(); state.resetCapture(); state.input = NSPasteboard.general.string(forType: .string) ?? ""; state.quote = ""; state.page = ""; panel.show(state: state); if !state.input.isEmpty { state.generate() } }
    func showDashboard(fullScreen: Bool = false) {
        startup.dismiss()
        guard let repository else { panel.show(state: state); return }
        panel.dismiss()
        if dashboardWindow == nil {
            dashboardWindow = makeWindow("CiteKit Dashboard", width: 1240, height: 820,
                content: DashboardView(repository: repository, state: dashboardState,
                    onCapture: { [weak self] in
                        guard let self else { return }
                        self.state.resetCapture(); self.state.input = ""; self.state.quote = ""; self.state.page = ""
                        self.panel.show(state: self.state)
                    },
                    onSearch: { [weak self] in
                        guard let self else { return }
                        self.state.beginSearch(); self.panel.show(state: self.state)
                    },
                    onSettings: { [weak self] in self?.showSettings() },
                    onFullScreen: { [weak self] in self?.dashboardWindow?.toggleFullScreen(nil) }))
            dashboardWindow?.collectionBehavior = [.fullScreenPrimary]
            dashboardWindow?.minSize = NSSize(width: 1040, height: 720)
            dashboardWindow?.setFrameAutosaveName("CiteKitDashboard")
        }
        dashboardWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if fullScreen, let window = dashboardWindow, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
    func showHistory() {
        startup.dismiss()
        guard let repository else { panel.show(state: state); return }
        if historyWindow == nil {
            historyWindow = makeWindow("Research history", width: 820, height: 610, content: HistoryView(state: historyState, repository: repository))
        }
        historyWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func showSettings() {
        startup.dismiss()
        if settingsWindow == nil { settingsWindow = makeWindow("CiteKit Preferences", width: 620, height: 760, content: PreferencesView()) }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func makeWindow<V: View>(_ title: String, width: CGFloat, height: CGFloat, content: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.contentView = NSHostingView(rootView: content); window.center(); return window
    }
}
