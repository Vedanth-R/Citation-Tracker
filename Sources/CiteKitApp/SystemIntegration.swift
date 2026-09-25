import AppKit
import ApplicationServices
import Carbon
import SwiftUI
import QuartzCore

@MainActor final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    private var current: KeyboardShortcut?
    private var nextID: UInt32 = 1
    func register(_ shortcut: KeyboardShortcut = .standard) -> Bool {
        if current == shortcut { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                MainActor.assumeIsolated { Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue().action?() }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return false }
        }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x43495445, id: nextID), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else { return false }
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement; current = shortcut; nextID += 1
        return true
    }
}

enum SelectionReader {
    static var trusted: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    static func read() -> String? {
        guard trusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 1)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
        var focused = element(attribute(system, kAXFocusedUIElementAttribute))
        if focused == nil, let app = element(attribute(system, kAXFocusedApplicationAttribute)) {
            AXUIElementSetMessagingTimeout(app, 1)
            focused = element(attribute(app, kAXFocusedUIElementAttribute))
        }
        guard let focused else { return nil }
        AXUIElementSetMessagingTimeout(focused, 1)
        if let string = attribute(focused, kAXSelectedTextAttribute) as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return string }
        // Some document editors expose the selected range but not AXSelectedText.
        guard let rawRange = attribute(focused, kAXSelectedTextRangeAttribute), CFGetTypeID(rawRange) == AXValueGetTypeID() else { return nil }
        let value = unsafeBitCast(rawRange, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range), range.location >= 0, range.length > 0, range.length <= 100_000 else { return nil }
        var selected: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString, value, &selected) == .success, let text = selected as? String { return text }
        // Read only the explicit selected range from the focused text element.
        if let text = attribute(focused, kAXValueAttribute) as? String {
            return selectedSubstring(text, range: range)
        }
        return nil
    }
    static func selectedSubstring(_ text: String, range: CFRange) -> String? {
        let ns = text as NSString
        guard range.location >= 0, range.length > 0, range.location <= ns.length, range.length <= ns.length - range.location else { return nil }
        return ns.substring(with: NSRange(location: range.location, length: range.length))
    }
}

extension Notification.Name {
    static let citeKitPanelOpened = Notification.Name("CiteKitPanelOpened")
}
final class CitationPanel: NSPanel {
    var dismissAction: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { dismissAction?() }
}
@MainActor final class PanelController: NSObject, NSWindowDelegate {
    private var panel: CitationPanel?
    private var presentationID = UUID()
    private var screenFrame: NSRect = .zero
    private var desiredHeight: CGFloat = 300
    var onHistory: (() -> Void)?
    var onSettings: (() -> Void)?
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func show(state: AppState) {
        if panel == nil {
            let window = CitationPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: desiredHeight), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "CiteKit"; window.level = .floating; window.isFloatingPanel = true
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
            window.isMovableByWindowBackground = true
            window.hidesOnDeactivate = false; window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.dismissAction = { [weak self] in self?.dismiss() }
            window.contentView = NSHostingView(rootView: CaptureView(state: state,
                onDismiss: { [weak self] in self?.dismiss() },
                onHistory: { [weak self] in self?.onHistory?() },
                onSettings: { [weak self] in self?.onSettings?() },
                onHeightChange: { [weak self] height in self?.resize(to: height) }))
            window.delegate = self; panel = window
        }
        guard let panel else { return }
        presentationID = UUID()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let target = centeredFrame(height: desiredHeight)
        let wasVisible = panel.isVisible
        if !wasVisible {
            panel.alphaValue = reduceMotion ? 1 : 0
            panel.setFrame(reduceMotion ? target : target.offsetBy(dx: 0, dy: -6), display: false)
        } else { panel.setFrame(target, display: true) }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { NotificationCenter.default.post(name: .citeKitPanelOpened, object: nil) }
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(centeredFrame(height: desiredHeight), display: true)
            }
        } else { panel.alphaValue = 1 }
    }
    private func centeredFrame(height: CGFloat) -> NSRect {
        let width = min(CGFloat(640), screenFrame.width - 40)
        let h = min(height, screenFrame.height - 80)
        let top = screenFrame.maxY - min(CGFloat(150), screenFrame.height * 0.18)
        return NSRect(x: screenFrame.midX - width / 2, y: max(screenFrame.minY + 24, top - h), width: width, height: h)
    }
    private func resize(to height: CGFloat) {
        desiredHeight = height
        guard let panel, panel.isVisible, screenFrame.width > 0 else { return }
        var frame = panel.frame
        let h = min(height, screenFrame.height - 80)
        frame.origin.y = max(screenFrame.minY + 24, frame.maxY - h)
        frame.size.height = h
        if abs(panel.frame.height - h) < 1 { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }
    func dismiss() {
        guard let panel, panel.isVisible else { return }
        let id = UUID(); presentationID = id
        if reduceMotion { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.presentationID == id else { return }
                self.panel?.orderOut(nil)
            }
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        guard panel?.attachedSheet == nil else { return }
        dismiss()
    }
}
