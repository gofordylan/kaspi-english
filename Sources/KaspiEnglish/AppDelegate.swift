import AppKit
import SwiftUI
import Carbon.HIToolbox
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let state = AppState()
    let bridge = TranslationBridge()
    lazy var glossary = Glossary()
    lazy var pipeline = Pipeline(state: state, glossary: glossary, bridge: bridge)

    private var statusItem: NSStatusItem!
    private var overlay: OverlayWindow!
    private var tracker: FrameTracker!
    private var panel: NSPanel?
    private var welcome: NSWindow?
    private var picker: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        bridge.state = state
        setUpStatusItem()
        setUpOverlay()
        setUpHotKeys()

        Task { await bridge.refreshAvailability() }
        pipeline.start()

        // Re-check translation availability whenever the app becomes active (e.g. after downloading in Settings).
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.bridge.refreshAvailability() }
                self.state.hasScreenPermission = CGPreflightScreenCaptureAccess()
            }
            .store(in: &cancellables)

        // Nothing is persisted, so "first run" = "permission not granted yet".
        if !CGPreflightScreenCaptureAccess() { showWelcome() }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Kaspi in English")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "Kaspi in English: unofficial helper", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let status = NSMenuItem(title: state.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if state.appleTranslation != .ready {
            let t = NSMenuItem(title: state.appleTranslation.label, action: nil, keyEquivalent: "")
            t.isEnabled = false
            menu.addItem(t)
        }
        menu.addItem(.separator())

        menu.addItem(item("Show Overlay", #selector(toggleOverlay), key: "t", checked: state.overlayEnabled, hotkey: true))
        menu.addItem(item("Show Russian ↔ English Panel", #selector(togglePanel), key: "p", checked: state.panelVisible, hotkey: true))
        menu.addItem(item("Refresh Now", #selector(refresh), key: "r", hotkey: true))
        menu.addItem(item(state.paused ? "Resume" : "Pause", #selector(togglePause)))
        menu.addItem(item("Hide Overlay When Window Is Covered", #selector(toggleHideWhenCovered), checked: state.hideWhenCovered))
        menu.addItem(.separator())
        menu.addItem(item("Choose Window…", #selector(showPicker)))
        menu.addItem(item("Setup & Permissions…", #selector(showWelcome)))
        menu.addItem(item("About Kaspi in English", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", checked: Bool = false, hotkey: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        i.state = checked ? .on : .off
        if hotkey { i.keyEquivalentModifierMask = [.control, .option] }
        return i
    }

    // MARK: - Overlay

    private func setUpOverlay() {
        overlay = OverlayWindow()
        let host = NSHostingView(rootView: OverlayView(state: state, bridge: bridge))
        host.autoresizingMask = [.width, .height]
        overlay.contentView = host
        overlay.orderFrontRegardless()
        tracker = FrameTracker(state: state, window: overlay)
        tracker.start()
    }

    private func setUpHotKeys() {
        HotKeys.shared.register(keyCode: kVK_ANSI_T) { [weak self] in self?.toggleOverlay() }
        HotKeys.shared.register(keyCode: kVK_ANSI_P) { [weak self] in self?.togglePanel() }
        HotKeys.shared.register(keyCode: kVK_ANSI_R) { [weak self] in self?.refresh() }
    }

    // MARK: - Actions

    @objc func toggleOverlay() {
        state.overlayEnabled.toggle()
        if state.overlayEnabled { pipeline.forceRefresh() }
    }

    @objc func togglePanel() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            state.panelVisible = false
            return
        }
        let p = panel ?? makePanel()
        panel = p
        state.panelVisible = true
        positionPanel(p)
        p.orderFrontRegardless()
        pipeline.forceRefresh()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Kaspi in English"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.contentView = NSHostingView(rootView: SidePanelView(
            state: state,
            onChooseWindow: { [weak self] in self?.showPicker() },
            onSetup: { [weak self] in self?.showWelcome() }))
        return p
    }

    /// Next to the mirrored iPhone if there's room, otherwise top-right of the screen.
    private func positionPanel(_ p: NSPanel) {
        let size = p.frame.size
        let screen = overlay.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: visible.maxX - size.width - 20, y: visible.maxY - size.height - 20)
        if state.target != nil {
            let f = overlay.frame
            if f.maxX + size.width + 12 < visible.maxX {
                origin = NSPoint(x: f.maxX + 12, y: min(f.maxY - size.height, visible.maxY - size.height))
            } else if f.minX - size.width - 12 > visible.minX {
                origin = NSPoint(x: f.minX - size.width - 12, y: min(f.maxY - size.height, visible.maxY - size.height))
            }
        }
        origin.y = max(origin.y, visible.minY)
        p.setFrameOrigin(origin)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSPanel) === panel { state.panelVisible = false }
    }

    @objc func refresh() { pipeline.forceRefresh() }
    @objc func togglePause() { state.paused.toggle(); if !state.paused { pipeline.forceRefresh() } }
    @objc func toggleHideWhenCovered() { state.hideWhenCovered.toggle() }

    @objc func showPicker() {
        picker?.close()
        let view = WindowPickerView(currentID: pipeline.chosenWindowID) { [weak self] id in
            self?.pipeline.choose(windowID: id)
            self?.picker?.close()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Choose Window"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        picker = w
        bringToFront(w)
    }

    @objc func showWelcome() {
        if let welcome { bringToFront(welcome); return }
        let view = WelcomeView(
            state: state, bridge: bridge,
            onRequestPermission: { [weak self] in self?.requestScreenPermission() },
            onOpenSettings: { Self.openScreenRecordingSettings() },
            onRelaunch: { Self.relaunch() },
            onDone: { [weak self] in self?.welcome?.close() })
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Welcome to Kaspi in English"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        welcome = w
        bringToFront(w)
    }

    @objc func showAbout() {
        let credits = NSAttributedString(
            string: "Free and open source: github.com/gofordylan/kaspi-english\n\n\(Brand.disclaimer)\n\nNo network access. Nothing is stored.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc func quit() { NSApp.terminate(nil) }

    private func bringToFront(_ w: NSWindow) {
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    // MARK: - Screen Recording permission

    private func requestScreenPermission() {
        // Shows the system prompt the first time and adds the app to the Screen Recording list.
        let granted = CGRequestScreenCaptureAccess()
        state.hasScreenPermission = granted
        if !granted { Self.openScreenRecordingSettings() }
    }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS only applies a new Screen Recording grant after the app restarts.
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
